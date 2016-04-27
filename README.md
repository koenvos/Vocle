Vocle is a Matlab tool to view, play and compare audio signals.

Vocle is inspired by Thomas Eriksson's spclab, and shares some of its behavior.  
Advantages over spclab:
- A/B test (select two signals)
- Stereo support
- Possible to interrrupt playback
- Scroll wheel zooming
- Use sampling rate info from input files, if available
- Remember window locations and sampling rate
- Auto update spectrum when highlighting a new segment
- Option to display spectrum on perceptual frequency scale
- Fix some spclab features that broke over time by changes in Matlab

Usage  
   Vocle([fs,] x, y);         Open vocle with signals x and y, optionally setting the sampling rate to fs  
   Vocle('x.wav', 'y.mp3');   Open vocle with files x.wav and y.mp3  
Vocle reads unrecognized file types as headerless 16-bit mono files. For these you can specify a
sampling rate as the first argument (or just set the sampling rate later in the menu). You may
also mix signals and files in the input arguments.

Navigation
- Left mouse:                Toggle axes selection
- Left mouse + drag:         Highlight segment
- Right mouse:
   - If highlight exists:    Zoom to highlighted segment; remove highlight
   - Otherwise:              Zoom out
- Double click left:         Zoom out full
- Shift + left/right:        Play
- Mouse click outside axes:  Remove highlight
- Mouse scroll:              Zoom in or out

Vocle requires Matlab 2014b or newer.
