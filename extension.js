// The module 'vscode' contains the VS Code extensibility API
// Import the module and reference it with the alias vscode in your code below
const vscode = require('vscode');
const fs = require('fs');
const path = require('path');

// Recording state
let isRecording = false;
let changeListener = null;
let logFilePath = null;
let logStream = null;
let lastLineLogged = -1;
let lastFileName = '';
// Dedupe: remember last logged content per file+line
/** @type {Map<string, Map<number, string>>} */
const lastLoggedLineTextByFile = new Map();
// Global dedupe: remember any line content we've already logged in this session (across files/lines)
/** @type {Set<string>} */
const seenLineContent = new Set();
// Agent / non-editor changes: track file writes via FS watcher and diff against snapshots
let fsWatcher = null;
/** @type {Map<string, string[]>} */
const fileSnapshotLinesByFileKey = new Map();
/** @type {Map<string, NodeJS.Timeout>} */
const pendingFsProcessByFileKey = new Map();
let openDocListener = null;
let recordingStartedAtMs = 0;
const FS_WARMUP_MS = 1000;

function isRecordingOutputFile(documentFsPath) {
	if (!documentFsPath) return false;
	const base = path.basename(documentFsPath);
	if (/^code-recording-.*\.txt$/i.test(base)) return true;
	if (logFilePath && path.resolve(documentFsPath) === path.resolve(logFilePath)) return true;
	return false;
}

function shouldIgnoreFsPath(documentFsPath) {
	if (!documentFsPath) return true;
	if (isRecordingOutputFile(documentFsPath)) return true;
	// Avoid massive noise
	if (documentFsPath.includes(`${path.sep}node_modules${path.sep}`)) return true;
	if (documentFsPath.includes(`${path.sep}.git${path.sep}`)) return true;
	return false;
}

/**
 * @param {string} fileKey
 * @param {number} lineNumberZeroBased
 * @param {string} nextText
 */
function shouldLogLine(fileKey, lineNumberZeroBased, nextText) {
	let byLine = lastLoggedLineTextByFile.get(fileKey);
	if (!byLine) {
		byLine = new Map();
		lastLoggedLineTextByFile.set(fileKey, byLine);
	}
	const prev = byLine.get(lineNumberZeroBased);
	// Always update the per-line cache so we don't re-trigger on the same line later
	byLine.set(lineNumberZeroBased, nextText);

	// 1) Per-line dedupe (same file+line text)
	if (prev === nextText) return false;

	// 2) Global dedupe (same text anywhere)
	if (seenLineContent.has(nextText)) return false;
	seenLineContent.add(nextText);
	return true;
}

/**
 * Schedule processing of a file change (debounced) so rapid agent writes don't spam I/O.
 * @param {vscode.Uri} uri
 */
function scheduleProcessFsUri(uri) {
	if (!isRecording || !logStream) return;
	if (!uri || uri.scheme !== 'file') return;
	if (shouldIgnoreFsPath(uri.fsPath)) return;
	// Avoid logging “startup churn” right when recording begins (language servers / autosave may touch files)
	if (recordingStartedAtMs && Date.now() - recordingStartedAtMs < FS_WARMUP_MS) return;

	const fileKey = uri.toString();
	const existing = pendingFsProcessByFileKey.get(fileKey);
	if (existing) clearTimeout(existing);

	const timeout = setTimeout(async () => {
		pendingFsProcessByFileKey.delete(fileKey);
		await processFsUri(uri);
	}, 200);

	pendingFsProcessByFileKey.set(fileKey, timeout);
}

/**
 * Read a file from disk and log changed lines vs last snapshot.
 * This catches edits made outside the normal editor keystroke pipeline (e.g., coding agents).
 * @param {vscode.Uri} uri
 */
async function processFsUri(uri) {
	if (!isRecording || !logStream) return;
	if (!uri || uri.scheme !== 'file') return;
	if (shouldIgnoreFsPath(uri.fsPath)) return;

	try {
		const buf = await fs.promises.readFile(uri.fsPath);
		// crude safety: skip huge files (>1MB)
		if (buf.length > 1024 * 1024) return;
		const text = buf.toString('utf8');
		const newLines = text.split(/\r?\n/);

		const fileKey = uri.toString();
		const prevLines = fileSnapshotLinesByFileKey.get(fileKey);

		// If we've never seen this file before during recording, treat current as baseline.
		// (We avoid logging the entire file the first time to reduce noise.)
		if (!prevLines) {
			fileSnapshotLinesByFileKey.set(fileKey, newLines);
			return;
		}

		const fileName = path.basename(uri.fsPath);
		const timestamp = new Date().toLocaleTimeString();
		const max = Math.max(prevLines.length, newLines.length);
		for (let i = 0; i < max; i++) {
			const prev = prevLines[i] ?? '';
			const next = newLines[i] ?? '';
			if (prev === next) continue;

			const normalized = next.replace(/^\s+/, '');
			if (normalized.trim().length === 0) continue;
			if (!shouldLogLine(fileKey, i, normalized)) continue;

			logStream.write(`[${timestamp}] ${fileName} | Line ${i + 1}: ${normalized}\n`);
		}

		fileSnapshotLinesByFileKey.set(fileKey, newLines);
	} catch (e) {
		// ignore read / decode errors
	}
}

/**
 * @param {vscode.ExtensionContext} context
 */
function activate(context) {
	// Start Recording command
	const startRecordingCommand = vscode.commands.registerCommand('vibe-learn.startRecording', function () {
		if (isRecording) {
			vscode.window.showWarningMessage('Recording is already in progress!');
			return;
		}

		// Create log file path in the workspace root
		const workspaceFolder = vscode.workspace.workspaceFolders?.[0];
		if (!workspaceFolder) {
			vscode.window.showErrorMessage('No workspace folder found. Please open a folder first.');
			return;
		}

		const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
		logFilePath = path.join(workspaceFolder.uri.fsPath, `code-recording-${timestamp}.txt`);

		// Initialize log file
		try {
			logStream = fs.createWriteStream(logFilePath, { flags: 'a' });
			logStream.write(`=== Recording Started: ${new Date().toLocaleString()} ===\n\n`);
			
			isRecording = true;
			recordingStartedAtMs = Date.now();
			lastLineLogged = -1;
			lastFileName = '';
			lastLoggedLineTextByFile.clear();
			seenLineContent.clear();
			fileSnapshotLinesByFileKey.clear();
			vscode.window.showInformationMessage('Recording started! Logging completed lines.');

			// Snapshot currently-open docs as baseline for FS diffs (so we don't log whole files on first save)
			vscode.workspace.textDocuments.forEach((doc) => {
				if (doc.uri.scheme !== 'file') return;
				if (shouldIgnoreFsPath(doc.uri.fsPath)) return;
				fileSnapshotLinesByFileKey.set(doc.uri.toString(), doc.getText().split(/\r?\n/));
			});

			// If the user opens a new file during recording, snapshot it as baseline to avoid “open-time” noise
			openDocListener = vscode.workspace.onDidOpenTextDocument((doc) => {
				if (!isRecording) return;
				if (doc.uri.scheme !== 'file') return;
				if (shouldIgnoreFsPath(doc.uri.fsPath)) return;
				const key = doc.uri.toString();
				if (!fileSnapshotLinesByFileKey.has(key)) {
					fileSnapshotLinesByFileKey.set(key, doc.getText().split(/\r?\n/));
				}
			});
			context.subscriptions.push(openDocListener);

			// Watch for file changes on disk (captures edits by agents / tools that bypass editor keystrokes)
			fsWatcher = vscode.workspace.createFileSystemWatcher('**/*');
			context.subscriptions.push(fsWatcher);
			fsWatcher.onDidCreate((uri) => scheduleProcessFsUri(uri));
			fsWatcher.onDidChange((uri) => scheduleProcessFsUri(uri));
			fsWatcher.onDidDelete((uri) => {
				if (!uri) return;
				const key = uri.toString();
				fileSnapshotLinesByFileKey.delete(key);
				const pending = pendingFsProcessByFileKey.get(key);
				if (pending) clearTimeout(pending);
				pendingFsProcessByFileKey.delete(key);
			});

			// Listen to document changes
			changeListener = vscode.workspace.onDidChangeTextDocument((event) => {
				if (!isRecording || !logStream) return;

				const document = event.document;
				if (document.uri.scheme !== 'file') return;
				if (isRecordingOutputFile(document.uri.fsPath)) return;

				const fileName = path.basename(document.fileName);
				const timestamp = new Date().toLocaleTimeString();
				const fileKey = document.uri.toString();

				event.contentChanges.forEach((change) => {
					const currentLine = change.range.start.line;

					// Log if: 
					// 1. User pressed Enter (\n)
					// 2. User moved to a different line (lastLineLogged !== currentLine)
					// 3. User switched to a different file (lastFileName !== fileName)
					if (change.text.includes('\n') || 
						(lastLineLogged !== -1 && (lastLineLogged !== currentLine || lastFileName !== fileName))) {
						
						// Determine which file and line to log
						// If we switched files, we log the PREVIOUS file/line we just left
						const fileToLog = (lastFileName !== '' && lastFileName !== fileName) ? lastFileName : fileName;
						const lineToLog = (lastLineLogged !== -1 && lastLineLogged !== currentLine) ? lastLineLogged : currentLine;
						const fileKeyToLog = (lastFileName !== '' && lastFileName !== fileName)
							? (vscode.workspace.textDocuments.find(d => path.basename(d.fileName) === lastFileName)?.uri.toString() || fileKey)
							: fileKey;
						
						try {
							// We need to find the correct document to get the text from if we switched files
							let textDocument = document;
							if (lastFileName !== '' && lastFileName !== fileName) {
								// Find the old document in open tabs if possible
								const oldDoc = vscode.workspace.textDocuments.find(d => path.basename(d.fileName) === lastFileName);
								if (oldDoc) textDocument = oldDoc;
							}

							const lineText = textDocument.lineAt(lineToLog).text;
							const normalizedLineText = lineText.replace(/^\s+/, '');
							if (normalizedLineText.trim().length > 0 && shouldLogLine(fileKeyToLog, lineToLog, normalizedLineText)) {
								logStream.write(`[${timestamp}] ${fileToLog} | Line ${lineToLog + 1}: ${normalizedLineText}\n`);
							}
						} catch (e) {
							// Fallback if the line or document is no longer accessible
						}
					}
					
					lastLineLogged = currentLine;
					lastFileName = fileName;
				});
			});

			context.subscriptions.push(changeListener);
		} catch (error) {
			vscode.window.showErrorMessage(`Failed to start recording: ${error.message}`);
			isRecording = false;
		}
	});

	// Stop Recording command
	const stopRecordingCommand = vscode.commands.registerCommand('vibe-learn.stopRecording', function () {
		if (!isRecording) {
			vscode.window.showWarningMessage('No recording in progress!');
			return;
		}

		// Flush the last line being worked on
		if (isRecording && logStream && lastLineLogged !== -1) {
			try {
				// Try to find the document for the last file we were editing
				const textDocument = vscode.workspace.textDocuments.find(d => path.basename(d.fileName) === lastFileName) 
				                  || vscode.window.activeTextEditor?.document;
				
				if (textDocument && textDocument.uri.scheme === 'file' && !isRecordingOutputFile(textDocument.uri.fsPath)) {
					const lineText = textDocument.lineAt(lastLineLogged).text;
					const normalizedLineText = lineText.replace(/^\s+/, '');
					if (normalizedLineText.trim().length > 0) {
						const timestamp = new Date().toLocaleTimeString();
						const key = textDocument.uri.toString();
						if (shouldLogLine(key, lastLineLogged, normalizedLineText)) {
							logStream.write(`[${timestamp}] ${path.basename(textDocument.fileName)} | Line ${lastLineLogged + 1}: ${normalizedLineText} (Final)\n`);
						}
					}
				}
			} catch (e) {
				// Ignore errors during final flush
			}
		}

		isRecording = false;

		// Close log file
		if (logStream) {
			logStream.write(`\n=== Recording Stopped: ${new Date().toLocaleString()} ===\n`);
			logStream.end();
			logStream = null;
		}

		// Dispose change listener
		if (changeListener) {
			changeListener.dispose();
			changeListener = null;
		}
		if (fsWatcher) {
			fsWatcher.dispose();
			fsWatcher = null;
		}
		if (openDocListener) {
			openDocListener.dispose();
			openDocListener = null;
		}
		recordingStartedAtMs = 0;
		pendingFsProcessByFileKey.forEach((t) => clearTimeout(t));
		pendingFsProcessByFileKey.clear();
		fileSnapshotLinesByFileKey.clear();

		if (logFilePath) {
			vscode.window.showInformationMessage(`Recording stopped! Log saved to: ${path.basename(logFilePath)}`);
			logFilePath = null;
		}
	});

	context.subscriptions.push(startRecordingCommand);
	context.subscriptions.push(stopRecordingCommand);
}

// This method is called when your extension is deactivated
function deactivate() {
	// Clean up if recording is still active
	if (isRecording && logStream) {
		logStream.write(`\n=== Recording Stopped (Extension Deactivated): ${new Date().toLocaleString()} ===\n`);
		logStream.end();
	}
	if (changeListener) {
		changeListener.dispose();
	}
}

module.exports = {
	activate,
	deactivate
}
