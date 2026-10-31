import test from 'node:test';
import assert from 'node:assert/strict';
import {assertMicrophoneSupport,microphoneErrorMessage} from '../public/phone-media.js';

test('voice capture requires a secure document and a real media capture API',()=>{
    assert.doesNotThrow(()=>assertMicrophoneSupport({secureContext:true,mediaDevices:{getUserMedia(){}}}));
    assert.throws(()=>assertMicrophoneSupport({secureContext:false,mediaDevices:{getUserMedia(){}}}),/secure HTTPS/);
    assert.throws(()=>assertMicrophoneSupport({secureContext:true,mediaDevices:{}}),/cannot access the microphone/);
});

test('a permission denial is explained as microphone access, not server failure',()=>{
    const message=microphoneErrorMessage({name:'NotAllowedError',message:'The request is not allowed by the user agent'});
    assert.match(message,/microphone access/);
    assert.match(message,/permission is already on/);
    assert(!message.includes('server'));
});

test('missing and busy microphones have different recovery advice',()=>{
    assert.match(microphoneErrorMessage({name:'NotFoundError'}),/No microphone/);
    assert.match(microphoneErrorMessage({name:'NotReadableError'}),/other app or call/);
});

test('unexpected microphone errors retain their useful details',()=>{
    assert.equal(microphoneErrorMessage({message:'Audio device disconnected'}),'Audio device disconnected');
    assert.match(microphoneErrorMessage(null),/microphone could not be started/);
});
