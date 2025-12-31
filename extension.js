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
			vscode.window.showInformationMessage('Recording started! Logging completed lines.');

			// Listen to document changes
			changeListener = vscode.workspace.onDidChangeTextDocument((event) => {
				if (!isRecording || !logStream) return;

				const document = event.document;
				const fileName = path.basename(document.fileName);
				const timestamp = new Date().toLocaleTimeString();

				event.contentChanges.forEach((change) => {
					console.log('change', change);
					console.log('change rangeLength', change.rangeLength);
					const currentLine = change.range.start.line;

					// 1. If user presses Enter (change contains newline)
					// 2. Or if user moved to a different line than the last one we tracked
					if (change.text.includes('\n') || (lastLineLogged !== -1 && lastLineLogged !== currentLine)) {
						
						// If we moved lines, log the line we just left
						const lineToLog = (lastLineLogged !== -1 && lastLineLogged !== currentLine) ? lastLineLogged : currentLine;
						const lineText = document.lineAt(lineToLog).text;

						if (lineText.trim().length > 0) {
							logStream.write(`[${timestamp}] ${fileName} | Line ${lineToLog + 1}: ${lineText}\n`);
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
				const editor = vscode.window.activeTextEditor;
				if (editor && editor.document) {
					const lineText = editor.document.lineAt(lastLineLogged).text;
					if (lineText.trim().length > 0) {
						const timestamp = new Date().toLocaleTimeString();
						logStream.write(`[${timestamp}] ${path.basename(editor.document.fileName)} | Line ${lastLineLogged + 1}: ${lineText} (Final)\n`);
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
