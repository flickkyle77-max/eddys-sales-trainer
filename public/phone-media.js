// A browser permission failure happens before the voice session reaches the server.
export function assertMicrophoneSupport({secureContext, mediaDevices}) {
    if (!secureContext) {
        throw new Error('Phone Training needs a secure HTTPS page. Open the training website directly or use the latest ObjectionIQ app.');
    }
    if (typeof mediaDevices?.getUserMedia !== 'function') {
        throw new Error('This browser cannot access the microphone. Open the training website in Safari or use the latest ObjectionIQ app.');
    }
}

export function microphoneErrorMessage(error) {
    switch (error?.name) {
    case 'NotAllowedError':
    case 'SecurityError':
        return 'Your device blocked microphone access. Check microphone permission in Settings. If permission is already on in the iPhone/iPad app, try Open in Safari from the app menu or install the latest app build.';
    case 'NotFoundError':
    case 'DevicesNotFoundError':
        return 'No microphone was found. Connect or enable a microphone, then try again.';
    case 'NotReadableError':
    case 'TrackStartError':
        return 'The microphone could not be opened. End any other app or call using it, then try again.';
    case 'OverconstrainedError':
    case 'ConstraintNotSatisfiedError':
        return 'This microphone cannot use the requested audio settings. Try another microphone or your device’s browser.';
    default:
        return error?.message || 'The microphone could not be started. Check its permission and try again.';
    }
}
