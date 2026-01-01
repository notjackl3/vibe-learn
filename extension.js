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

function isRecordingOutputFile(documentFsPath) {
	if (!documentFsPath) return false;
	const base = path.basename(documentFsPath);
	if (/^code-recording-.*\.txt$/i.test(base)) return true;
	if (logFilePath && path.resolve(documentFsPath) === path.resolve(logFilePath)) return true;
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
			lastLineLogged = -1;
			lastFileName = '';
			lastLoggedLineTextByFile.clear();
			seenLineContent.clear();
			vscode.window.showInformationMessage('Recording started! Logging completed lines.');

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
