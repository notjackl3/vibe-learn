// The module 'vscode' contains the VS Code extensibility API
const vscode = require('vscode');
const https = require('https');
const http = require('http');
const path = require('path');

// Recording state
let isRecording = false;
let currentSessionId = null;
let changeListener = null;
let lastLineLogged = -1;
let lastFileName = '';

// API Configuration
const API_URL = 'http://localhost:8080/api/events';
const API_KEY = 'custom-api-key-here'; // Match your docker-compose.yml

// Dedupe: remember last logged content per file + line number
/** @type {Map<string, Map<number, string>>} */
const lastLoggedLineTextByFile = new Map();

// Global dedupe: remember any line we've already logged
/** @type {Set<string>} */
const seenLineContent = new Set();

// Agent changes: track file writes via FS watcher and diff against snapshots
let fsWatcher = null;

// Track file snapshots, key is file URI and value is array of lines in the file
/** @type {Map<string, string[]>} */
const fileSnapshotLinesByFileKey = new Map();

// Track pending file process, key is file URI and value is timeout ID, used to debounce file changes
/** @type {Map<string, NodeJS.Timeout>} */
const pendingFsProcessByFileKey = new Map();

let openDocListener = null;
let recordingStartedAtMs = 0;
const FS_WARMUP_MS = 2000; // Increased warmup time to avoid initial noise

/**
 * Send a code event to the Ingest API
 * @param {Object} eventData
 */
async function sendEventToAPI(eventData) {
    return new Promise((resolve, reject) => {
        const data = JSON.stringify(eventData);
        const url = new URL(API_URL);

        const options = {
            hostname: url.hostname,
            port: url.port || 80,
            path: url.pathname,
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Content-Length': Buffer.byteLength(data),
                'X-API-Key': API_KEY
            }
        };

        const client = url.protocol === 'https:' ? https : http;

        const req = client.request(options, (res) => {
            let responseBody = '';

            res.on('data', (chunk) => {
                responseBody += chunk;
            });

            res.on('end', () => {
                if (res.statusCode >= 200 && res.statusCode < 300) {
                    resolve({ success: true, data: responseBody });
                } else {
                    reject(new Error(`API returned status ${res.statusCode}: ${responseBody}`));
                }
            });
        });

        req.on('error', (error) => {
            console.error('API request failed:', error);
            reject(error);
        });

        req.write(data);
        req.end();
    });
}

function shouldIgnoreFsPath(documentFsPath) {
    if (!documentFsPath) return true;
    // Avoid massive noise because node_modules changes a lot
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
 * Log a code line by sending it to the API
 */
async function logCodeLine(fileUri, fileName, lineNumber, textNormalized, source = 'manual') {
    if (!currentSessionId) return;

    const event = {
        sessionId: currentSessionId,
        clientTimestampMs: Date.now(),
        fileUri: fileUri,
        fileName: fileName,
        lineNumber: lineNumber + 1, // Convert 0-based to 1-based
        textNormalized: textNormalized,
        source: source
    };

    try {
        await sendEventToAPI(event);
        console.log(`✅ Sent event: ${fileName}:${lineNumber + 1} [${source}]`);
    } catch (error) {
        console.error('❌ Failed to send event:', error.message);
        // Don't show error to user to avoid spam, just log it
    }
}

/**
 * Schedule processing of a file change (debounced) so rapid agent writes don't spam I/O.
 * @param {vscode.Uri} uri
 */
function scheduleProcessFsUri(uri) {
    if (!isRecording) return;
    if (!uri || uri.scheme !== 'file') return;
    if (shouldIgnoreFsPath(uri.fsPath)) return;

    // Avoid logging startup noise right when recording begins
    if (recordingStartedAtMs && Date.now() - recordingStartedAtMs < FS_WARMUP_MS) {
        return;
    }

    const fileKey = uri.toString();
    const existing = pendingFsProcessByFileKey.get(fileKey);
    if (existing) clearTimeout(existing);

    const timeout = setTimeout(async () => {
        pendingFsProcessByFileKey.delete(fileKey);
        await processFsUri(uri);
    }, 300); // Slightly longer debounce to reduce noise

    pendingFsProcessByFileKey.set(fileKey, timeout);
}

/**
 * Read a file from disk and log changed lines vs last snapshot.
 * This catches edits made outside the normal editor keystroke pipeline (e.g., coding agents).
 * @param {vscode.Uri} uri
 */
async function processFsUri(uri) {
    if (!isRecording) return;
    if (!uri || uri.scheme !== 'file') return;
    if (shouldIgnoreFsPath(uri.fsPath)) return;

    // Skip if still in warmup period
    if (recordingStartedAtMs && Date.now() - recordingStartedAtMs < FS_WARMUP_MS) {
        return;
    }

    try {
        const document = await vscode.workspace.openTextDocument(uri);
        const text = document.getText();

        // crude safety: skip huge files (>1MB)
        if (text.length > 1024 * 1024) return;

        const newLines = text.split(/\r?\n/);
        const fileKey = uri.toString();
        const prevLines = fileSnapshotLinesByFileKey.get(fileKey);

        // If we've never seen this file before during recording, treat current as baseline.
        // DO NOT LOG - just save the snapshot for future comparisons
        if (!prevLines) {
            fileSnapshotLinesByFileKey.set(fileKey, newLines);
            return;
        }

        const fileName = path.basename(uri.fsPath);
        const max = Math.max(prevLines.length, newLines.length);

        for (let i = 0; i < max; i++) {
            const prev = prevLines[i] ?? '';
            const next = newLines[i] ?? '';
            if (prev === next) continue;

            const normalized = next.replace(/^\s+/, '');
            if (normalized.trim().length === 0) continue;
            if (!shouldLogLine(fileKey, i, normalized)) continue;

            // Send to API with source='agent' since it's a file system change
            await logCodeLine(fileKey, fileName, i, normalized, 'agent');
        }

        fileSnapshotLinesByFileKey.set(fileKey, newLines);
    } catch (e) {
        console.error('Failed to process file:', e);
    }
}

/**
 * @param {vscode.ExtensionContext} context
 */
function activate(context) {
    // Start Recording command
    const startRecordingCommand = vscode.commands.registerCommand('vibe-learn.startRecording', async function () {
        if (isRecording) {
            vscode.window.showWarningMessage('Recording is already in progress!');
            return;
        }

        // Prompt for session ID
        const sessionId = await vscode.window.showInputBox({
            prompt: 'Enter a session ID for this recording',
            placeHolder: 'e.g., feature-login-page, debug-session-1',
            validateInput: (value) => {
                if (!value || value.trim().length === 0) {
                    return 'Session ID cannot be empty';
                }
                return null;
            }
        });

        if (!sessionId) {
            return; // User cancelled
        }

        currentSessionId = sessionId.trim();

        try {
            isRecording = true;
            recordingStartedAtMs = Date.now();
            lastLineLogged = -1;
            lastFileName = '';
            lastLoggedLineTextByFile.clear();
            seenLineContent.clear();
            fileSnapshotLinesByFileKey.clear();

            vscode.window.showInformationMessage(`🎙️ Recording started for session: ${currentSessionId}`);
            console.log(`🎙️ Recording started at ${new Date().toLocaleTimeString()}`);

            // CRITICAL: Snapshot currently-open docs as baseline
            // We DON'T log these - just store them to detect FUTURE changes
            vscode.workspace.textDocuments.forEach((doc) => {
                if (doc.uri.scheme !== 'file') return;
                if (shouldIgnoreFsPath(doc.uri.fsPath)) return;
                const lines = doc.getText().split(/\r?\n/);
                fileSnapshotLinesByFileKey.set(doc.uri.toString(), lines);
                console.log(`📸 Snapshotted baseline: ${path.basename(doc.uri.fsPath)} (${lines.length} lines)`);
            });

            // If the user opens a new file during recording, snapshot it as baseline
            openDocListener = vscode.workspace.onDidOpenTextDocument((doc) => {
                if (!isRecording) return;
                if (doc.uri.scheme !== 'file') return;
                if (shouldIgnoreFsPath(doc.uri.fsPath)) return;
                const key = doc.uri.toString();
                if (!fileSnapshotLinesByFileKey.has(key)) {
                    const lines = doc.getText().split(/\r?\n/);
                    fileSnapshotLinesByFileKey.set(key, lines);
                    console.log(`📸 Snapshotted new file: ${path.basename(doc.uri.fsPath)} (${lines.length} lines)`);
                }
            });
            context.subscriptions.push(openDocListener);

            // Watch for file changes on disk (captures edits by agents / tools)
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

            // Listen to document changes (manual typing)
            changeListener = vscode.workspace.onDidChangeTextDocument(async (event) => {
                if (!isRecording) return;

                const document = event.document;
                if (document.uri.scheme !== 'file') return;
                if (shouldIgnoreFsPath(document.uri.fsPath)) return;

                const fileName = path.basename(document.fileName);
                const fileKey = document.uri.toString();

                // Initialize snapshot for this file if not already done
                if (!fileSnapshotLinesByFileKey.has(fileKey)) {
                    const lines = document.getText().split(/\r?\n/);
                    fileSnapshotLinesByFileKey.set(fileKey, lines);
                    console.log(`📸 Snapshotted on first edit: ${fileName} (${lines.length} lines)`);
                }

                event.contentChanges.forEach(async (change) => {
                    const currentLine = change.range.start.line;

                    // Log if:
                    // 1. User pressed Enter (\n)
                    // 2. User moved to a different line
                    // 3. User switched to a different file
                    if (change.text.includes('\n') ||
                        (lastLineLogged !== -1 && (lastLineLogged !== currentLine || lastFileName !== fileName))) {

                        const fileToLog = (lastFileName !== '' && lastFileName !== fileName) ? lastFileName : fileName;
                        const lineToLog = (lastLineLogged !== -1 && lastLineLogged !== currentLine) ? lastLineLogged : currentLine;
                        const fileKeyToLog = (lastFileName !== '' && lastFileName !== fileName)
                            ? (vscode.workspace.textDocuments.find(d => path.basename(d.fileName) === lastFileName)?.uri.toString() || fileKey)
                            : fileKey;

                        try {
                            let textDocument = document;
                            if (lastFileName !== '' && lastFileName !== fileName) {
                                const oldDoc = vscode.workspace.textDocuments.find(d => path.basename(d.fileName) === lastFileName);
                                if (oldDoc) textDocument = oldDoc;
                            }

                            const lineText = textDocument.lineAt(lineToLog).text;
                            const normalizedLineText = lineText.replace(/^\s+/, '');

                            if (normalizedLineText.trim().length > 0 && shouldLogLine(fileKeyToLog, lineToLog, normalizedLineText)) {
                                await logCodeLine(fileKeyToLog, fileToLog, lineToLog, normalizedLineText, 'manual');
                            }
                        } catch (e) {
                            console.error('Failed to log line:', e);
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
            currentSessionId = null;
        }
    });

    // Stop Recording command
    const stopRecordingCommand = vscode.commands.registerCommand('vibe-learn.stopRecording', async function () {
        if (!isRecording) {
            vscode.window.showWarningMessage('No recording in progress!');
            return;
        }

        // Flush the last line being worked on
        if (isRecording && lastLineLogged !== -1) {
            try {
                const textDocument = vscode.workspace.textDocuments.find(d => path.basename(d.fileName) === lastFileName)
                    || vscode.window.activeTextEditor?.document;

                if (textDocument && textDocument.uri.scheme === 'file' && !shouldIgnoreFsPath(textDocument.uri.fsPath)) {
                    const lineText = textDocument.lineAt(lastLineLogged).text;
                    const normalizedLineText = lineText.replace(/^\s+/, '');
                    if (normalizedLineText.trim().length > 0) {
                        const key = textDocument.uri.toString();
                        if (shouldLogLine(key, lastLineLogged, normalizedLineText)) {
                            await logCodeLine(key, path.basename(textDocument.fileName), lastLineLogged, normalizedLineText, 'manual');
                        }
                    }
                }
            } catch (e) {
                console.error('Failed to flush final line:', e);
            }
        }

        const sessionId = currentSessionId;
        isRecording = false;
        currentSessionId = null;

        // Dispose listeners
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

        vscode.window.showInformationMessage(`⏹️ Recording stopped for session: ${sessionId}`);
        console.log(`⏹️ Recording stopped at ${new Date().toLocaleTimeString()}`);
    });

    context.subscriptions.push(startRecordingCommand);
    context.subscriptions.push(stopRecordingCommand);
}

// This method is called when your extension is deactivated
function deactivate() {
    // Clean up if recording is still active
    if (isRecording) {
        isRecording = false;
        currentSessionId = null;
    }
    if (changeListener) {
        changeListener.dispose();
    }
    if (fsWatcher) {
        fsWatcher.dispose();
    }
    if (openDocListener) {
        openDocListener.dispose();
    }
}

module.exports = {
    activate,
    deactivate
}