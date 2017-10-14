Vocle is a Matlab tool to view, play, and compare audio signals.

Features:
- Load workspace signals or sound files
- Play signals or segments
- Blind A/B test two signals
- View spectrum, on linear or perceptual scale
- View spectrogram
- Mono and stereo support

Usage  
- Vocle([fs,] x, y);         Open vocle with signals x and y, optionally setting the sampling rate to fs  
- Vocle('x.wav', 'y.mp3');   Open vocle with files x.wav and y.mp3  
Vocle reads unrecognized file types as headerless 16-bit mono files. For these you can specify a
sampling rate as the first argument (or just set the sampling rate later in the menu). You may
also combine signals and files in the input arguments.

Navigation
Mouse:
- Left mouse:                Select/deselect signal
- Left mouse + drag:         Highlight segment
- Right mouse:
  - If highlight exists:     Zoom to highlighted segment; remove highlight
  - Otherwise:               Zoom out
- Double click left:         Zoom out full
- Mouse click outside axes:  Remove highlight
- Mouse scroll:              Zoom in or out
- Shift + left/right mouse:  Play start/stop
Keyboard:
- Space bar:                 Play start/stop
- Arrow left/right:          Scroll horizontally
- Arrow up/down:             Zoom in/out

Vocle is inspired by Thomas Eriksson's spclab, and shares some of its behavior.  

Vocle requires Matlab 2014b or newer.
