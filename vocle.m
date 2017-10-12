function vocle(varargin)
% VOCLE Audio navigator
%  Vocle lets you view, play and compare audio signals.
%
%  Vocle is inspired by Thomas Eriksson's spclab, and shares some of its behavior. 
%  Advantages over spclab:
%   - A/B test (select two signals)
%   - Stereo support
%   - Possible to interrrupt playback
%   - Scroll wheel zooming
%   - Use sampling rate info from input files, if available
%   - Remember window locations and sampling rate
%   - Auto update spectrum and spectrogram when highlighting a new segment
%   - Option to display spectrum on perceptual frequency scale
%   - Fix some spclab features that broke over time by changes in Matlab
%
%  Usage
%     vocle([fs,] x, y);         Open vocle with signals x and y, optionally setting the sampling rate to fs 
%     vocle('x.wav', 'y.mp3');   Open vocle with files x.wav and y.mp3
%  Vocle reads unrecognized file types as headerless 16-bit mono files. For these you can specify a
%  sampling rate as the first argument (or set the sampling rate later in the menu). You may also
%  use a combination of signals and files in the input arguments.
% 
%  Navigation
%     Left mouse:                Toggle axes selection
%     Left mouse + drag:         Highlight segment
%     Right mouse:
%      - If highlight exists:    Zoom to highlighted segment; remove highlight
%      - Otherwise:              Zoom out
%     Double click left:         Zoom out full
%     Shift + left/right:        Play
%     Mouse click outside axes:  Remove highlight
%     Mouse scroll:              Zoom in or out
%
%  Vocle requires Matlab 2014b or newer.

%  License: Vocle is free, open source and, to my knowledge, unencumbered by patents. Feel free to use 
%  Vocle in any way you want, but don't blame me if it blows out your ears or other unpleasentness happens.
%  Copyright 2016, 2017 Koen Vos

if verLessThan('matlab', 'R2014b')
    disp('Sorry, your Matlab version is too old. Vocle requires at least R2014b..')
    return;
end

global voctone_h_fig voctone_h_spec;

% settings
enable_edit_mode = 0;  % overwrite signal segment with value from 0...9 by pressing corresponding number key
fig_no = 937280;
axes_label_font_size = 8;
left_margin = 42;
right_margin = 22;
bottom_margin = 80;
bottom_margin_spec = 38;
top_margin = 12;
vert_spacing = 23;
slider_height = 16;
figure_color = [0.9, 0.9, 0.9];
if 1
    axes_color = [0.93, 0.93, 0.93];
    selection_color = [1, 1, 1];
    highlight_color = [0.73, 0.82, 0.91];
else
    axes_color = [1, 1, 1];
    selection_color = [0.9, 0.95, 1];
    highlight_color = [0.75, 0.85, 0.95];
end
marker_color = [0.2, 0.3, 0.5];
zoom_per_scroll_wheel_step = 1.4;
max_zoom_smpls = 6;
max_horizontal_resolution = 1e5;
ylim_margin = 1.1;
min_abs_signal = 1e-99;
min_selection_frac = 0.002;
file_fs = [192000, 96000, 48000, 44100, 32000, 16000, 8000];  % in menu
default_fs = 48000;  % of input signal, assumed unless otherwise indicated or remembered
playback_fs = 44100; % of signal played to soundcard
playback_bits = 24;
playback_dBov = -1;
playback_cursor_delay_ms = 50;
playback_silence_between_A_B_ms = 500;
spectrum_sampling_Hz = 2;
spectrum_smoothing_Hz = 20;
spectrum_perc_fc_Hz = 500;
spectrum_perc_smoothing = 0.025;
specgram_win_ms = [5, 10, 20, 40, 70];  % window lengths should be a multiple of 10 ms to handle 44100 Hz
verbose = 0;

% function-wide variables
h_ax = [];
selected_axes = [];
time_range_view = [];
highlight_range = [];
highlight_markers = {};
player = [];
play_cursors = {};

% try to load configuration
config = [];
config_file = [which('vocle'), 'at'];
if exist(config_file, 'file')
    load(config_file, 'config');
end

% open figure and use position from config file
voctone_h_fig = figure(fig_no);
if isfield(config, 'Position')
    voctone_h_fig.Position = config.Position;
end
clf(voctone_h_fig);
voctone_h_fig.NumberTitle = 'off';
voctone_h_fig.Name = ' Vocle';
voctone_h_fig.Color = figure_color;
voctone_h_fig.ToolBar = 'none';
voctone_h_fig.MenuBar = 'none';
voctone_h_fig.WindowKeyPressFcn = @keypress_callback;
h_file = uimenu(voctone_h_fig, 'Label', '&File', 'Callback', @menu_callback);
uimenu(h_file, 'Label', 'Open', 'Callback', @open_file_callback);
h_save = uimenu(h_file, 'Label', 'Save Signal', 'Callback', @save_file_callback);
% the following line uses the undocumented function filemenufcn()... might break
uimenu(h_file, 'Label', 'Save Figure', 'Callback', 'filemenufcn(gcbf, ''FileSaveAs'')');
h_visualize = uimenu(voctone_h_fig, 'Label', '&Visualize', 'Callback', @menu_callback);
h_spectrum_menu = uimenu(h_visualize, 'Label', 'Spectrum', 'Callback', @spectrum_callback);
h_specgram_menu = uimenu(h_visualize, 'Label', 'Spectrogram', 'Callback', @spectrogram_callback);
h_close_all_spec = uimenu(h_visualize, 'Label', 'Close all', 'Callback', @window_close_all_callback);
h_settings = uimenu(voctone_h_fig, 'Label', '&Settings', 'Callback', @menu_callback);
h_fs = uimenu(h_settings, 'Label', 'Sampling Rate');
for k = 1:length(file_fs)
    uimenu(h_fs, 'Label', num2str(file_fs(k)), 'Callback', @change_fs_callback);
end
h_f_scale = uimenu(h_settings, 'Label', 'Spectrum Scale');
uimenu(h_f_scale, 'Label', 'Linear', 'Callback', @spec_scale_callback);
uimenu(h_f_scale, 'Label', 'Perceptual', 'Callback', @spec_scale_callback);
if ~isfield(config, 'spectrum_scale')
    % default
    config.spectrum_scale = 'Perceptual';
end    
set(findall(h_f_scale.Children, 'Label', config.spectrum_scale), 'Checked', 'on');
h_sg_win = uimenu(h_settings, 'Label', 'Spectrogram Window');
for k = 1:length(specgram_win_ms)
    uimenu(h_sg_win, 'Label', [num2str(specgram_win_ms(k)), ' ms'], 'Callback', @change_spectrogram_win_callback);
end
if ~isfield(config, 'specgram_win') || isempty(findall(h_sg_win.Children, 'Label', config.specgram_win))
    % default
    config.specgram_win = [num2str(specgram_win_ms(floor(end/2+1))), ' ms'];
end
set(findall(h_sg_win.Children, 'Label', config.specgram_win), 'Checked', 'on');


% process inputs
% check if first argument is sampling rate, otherwise use the config value
first_arg_fs = 0;
if length(varargin)>1 && isscalar(varargin{1}) && isnumeric(varargin{1})
    config.fs = varargin{1};
    first_arg_fs = 1;
elseif ~isfield(config, 'fs')
    config.fs = default_fs;
end
num_signals = length(varargin) - first_arg_fs;
highlight_patches = cell(num_signals, 1);
signals = cell(num_signals, 1);
signal_lengths = config.fs;  % default, in case of no input args
signals_negative = zeros(num_signals, 1);
signals_positive = zeros(num_signals, 1);
signals_max = zeros(num_signals, 1);
file_fs = zeros(num_signals, 1);
for k = 1:num_signals
    arg = varargin{k+first_arg_fs};
    if ischar(arg)
        % file name
        if ~exist(arg, 'file')
            error(['  file not found: ', varargin{k}]);
        else
            try
                if 0
                    % read as doubles (seems slower)
                    [signals{k}, file_fs(k)] = audioread(arg);
                else
                    % read as native and convert to doubles (seems faster)
                    [signals{k}, file_fs(k)] = audioread(arg, 'native');
                    if isinteger(signals{k})
                        data_format = class(signals{k});
                        max_val = single(max(abs([intmin(data_format), intmax(data_format)])));
                    else
                        max_val = 1;
                    end
                    signals{k} = single(signals{k}) / max_val;
                end
            catch
                % read as shorts without header
                arg_split = strsplit(arg, '\\');
                disp(['Reading as raw int16: ', arg_split{end}]);
                fid = fopen(arg, 'rb');
                signals{k} = single(fread(fid, inf, 'short') / 32768);
                fclose(fid);
            end
        end
    else
        sz = size(arg);
        if sz(1) > sz(2)
            signals{k} = arg;
        else
            signals{k} = arg';
        end
    end
end
if any(file_fs)
    config.fs = max(max(file_fs), first_arg_fs * config.fs);
end
signals_fs = file_fs;
signals_fs(file_fs == 0) = config.fs;
set(findall(h_fs.Children, 'Label', num2str(config.fs)), 'Checked', 'on');
for k = 1:num_signals
    if ~isreal(signals{k})
        disp(['Warning: signal ', num2str(k), ' is complex; ignoring imaginary part']);
        signals{k} = real(signals{k});
    end
    if any(isnan(signals{k}))
        disp(['Warning: signal ', num2str(k), ' contains NaNs; replacing these by zeros']);
        signals{k}(isnan(signals{k})) = 0;
    end
    signal_lengths(k, 1) = size(signals{k}, 1);
    
    % for long signals, repeatedly reduce 4x in length and store
    level = 1;
    [L, M] = size(signals{k, level});
    while L > max_horizontal_resolution
        L2 = ceil(L / 8);
        s = zeros(2 * L2, M);
        for m = 1:M
            tmp = reshape([signals{k, level}(:, m); zeros(8 * L2 - L, 1)], 8, L2);
            tmp = [min(tmp); max(tmp)];
            s(:, m) = tmp(:);
        end
        signals{k, level+1} = s;
        level = level + 1;
        [L, M] = size(s);
    end
    
    % find min/max
    s = s(:);
    signals_negative(k) = min(s) < 0;
    signals_positive(k) = max(s) > 0;
    signals_max(k) = max(max(abs(s)), min_abs_signal);
end

write_config;
if isempty(voctone_h_spec)
    % allocate new graphics array for spectrum and spectrograms
    voctone_h_spec = gobjects(num_signals+1, 1);
else
    % remove deleted handles
    voctone_h_spec = voctone_h_spec(isgraphics(voctone_h_spec));
    % add "old" to figure titles
    for k = 1:length(voctone_h_spec)
        voctone_h_spec(k).Name = [voctone_h_spec(k).Name, ' old'];
    end    
    % allocate new graphics array and append old ones
    voctone_h_spec = [gobjects(num_signals+1, 1); voctone_h_spec];
end


% add elements to UI
h_ax = cell(num_signals, 1);
for k = 1:num_signals
    h_ax{k} = axes;
    h_ax{k}.Units = 'pixels';
end
text_segment = uicontrol(voctone_h_fig, 'Style', 'text', 'FontName', 'Helvetica', ...
    'BackgroundColor', [1, 1, 1], 'Visible', 'off', 'HitTest', 'Off');
time_slider = uicontrol(voctone_h_fig, 'Style', 'slider', 'Value', 0.5, 'BackgroundColor', axes_color);
slider_listener = addlistener(time_slider, 'Value', 'PostSet', @slider_moved_callback);
play_button = uicontrol(voctone_h_fig, 'Style', 'pushbutton', 'String', 'Play', 'FontSize', 9, 'Callback', @start_play);

update_layout;

% show signals
update_axes_selections([], 'reset');
set_time_range([0, inf], 1);
update_play_button;

% set figure callbacks
voctone_h_fig.CloseRequestFcn = @window_close_all_callback;
voctone_h_fig.SizeChangedFcn = @window_resize_callback;
voctone_h_fig.ButtonDownFcn = @window_button_down_callback;
voctone_h_fig.WindowScrollWheelFcn = @window_scroll_callback;
voctone_h_fig.WindowButtonUpFcn = '';

    % position UI elements
    function update_layout
        h_width = voctone_h_fig.Position(3);
        h_height = voctone_h_fig.Position(4);
        width = h_width - left_margin - right_margin;
        height = (h_height - top_margin - bottom_margin - (num_signals-1) * vert_spacing) / max(num_signals, 1);
        if height > 0 && width > 0
            for kk = 1:num_signals
                bottom = bottom_margin + (num_signals - kk) * (height + vert_spacing);
                h_ax{kk}.Position = [left_margin, bottom, width, height];
            end
        end
        slider_bottom = bottom_margin - vert_spacing - slider_height;
        time_slider.Position = [left_margin-10, slider_bottom, width+20, slider_height];
        play_button.Position = [left_margin+width/2-30, (slider_bottom-22)/2, 60, 22];  % extra big
    end

    function open_file_callback(~, ~)
        file_types = {'*.wav;*.mp3;*.mp4;*.m4a;*.flac;*.ogg;*.pcm;*.raw)', ...
            'Audio files (*.wav,*.mp3,*.mp4,*.m4a,*.flac,*.ogg,*.pcm,*.raw)'};
        [file_names, path_name] = uigetfile(file_types, 'Open audio file(s)', 'MultiSelect', 'on');
        if isempty(file_names)
            return;
        end
        str = 'vocle(';
        if iscell(file_names)
            disp('Order:');
            for kk = 1:length(file_names)-1
                disp(file_names{kk});
                str = [str, '''', path_name file_names{kk}, ''', '];
            end
            disp(file_names{end});
            str = [str, '''', path_name file_names{end}, ''');'];
            eval(str);
        elseif file_names ~= 0
            str = [str, '''', path_name file_names, ''');'];
            eval(str);
        end
    end

    function save_file_callback(~, ~)
        if diff(highlight_range)
            title_str = 'Save highlighted segment';
        else
            title_str = 'Save selected signal';
        end
        file_types = {'*.wav'; '*.m4a'; '*.mat'};
        kk = find(selected_axes);
        for i = 1:length(kk)
            kkk = kk(i);
            [file_name, path_name, file_type_ix] = uiputfile(file_types, title_str, ['signal', num2str(kkk), '.wav']);
            if ischar(path_name) && ischar(file_name)
                signal = get_current_signal(kkk, signals_fs(kkk), 0);
                if isempty(signal)
                    return;
                end
                if file_type_ix ~= length(file_types)
                    % audio file
                    % avoid clipping
                    max_abs = max(abs(signal(:)));
                    if max_abs > 1
                        signal = signal / max_abs;
                        warning(['Reduced signal ', num2str(kkk), ' by ', num2str(20*log10(max_abs), 3), ' dB to avoid clipping'])
                    end
                    audiowrite([path_name, file_name], signal, signals_fs(kkk));
                else
                    % MAT file
                    save([path_name, file_name], 'signal');
                end
            end
        end
    end

    function update_axes_selections(ind, type)
        if num_signals == 1
            selected_axes = 1;
        else
            switch(type)
                case 'reset'
                    selected_axes = zeros(num_signals, 1);
                case 'toggle'
                    selected_axes(ind) = 1 - selected_axes(ind);
            end
        end
        for kk = 1:num_signals
            h_ax{kk}.Color = selection_color * selected_axes(kk) + axes_color * (1-selected_axes(kk));
        end
    end

    function update_play_button
        if ~isempty(player) && player.isplaying  % don't disable during playback
            play_button.String = 'Stop';
            play_button.Enable = 'on';
        elseif sum(selected_axes) == 1
            play_button.String = 'Play';
            play_button.Enable = 'on';
        elseif sum(selected_axes) == 2
            play_button.String = 'A/B';
            play_button.Enable = 'on';
        else
            play_button.String = 'Play';
            play_button.Enable = 'off';
        end
    end

    function menu_callback(~, ~)
        % update menu strings where necessary
        if sum(selected_axes) == 0
            h_spectrum_menu.Enable = 'off';
            h_specgram_menu.Enable = 'off';
            h_save.Enable = 'off';
        else
            h_spectrum_menu.Enable = 'on';
            h_specgram_menu.Enable = 'on';
            h_save.Enable = 'on';
        end
        if sum(selected_axes) > 1
            h_save.Label = 'Save Signals';
        else
            h_save.Label = 'Save Signal';
        end
        if any(isgraphics(voctone_h_spec))
            h_close_all_spec.Enable = 'on';
        else
            h_close_all_spec.Enable = 'off';
        end
    end

    % plot signals
    function plot_signals
        tmp_range = highlight_range;
        delete_highlights;   % they wouldn't survive the plotting
        for kk = 1:num_signals
            t0_smpls = max(floor(time_range_view(1)*signals_fs(kk)), 1);
            t1_smpls = min(ceil(time_range_view(2)*signals_fs(kk)), signal_lengths(kk));
            len = t1_smpls - t0_smpls;
            if len > max_horizontal_resolution
                level = ceil(0.5 * log2(len / max_horizontal_resolution));
                s = signals{kk, level+1};
                d = 4^level;
                t0_smpls = ceil((t0_smpls-1) / d) + 1;
                t1_smpls = floor((t1_smpls-1) / d) + 1;
            else
                s = signals{kk};
                d = 1;
            end
            s = s(t0_smpls:t1_smpls, :);
            t = (t0_smpls + (0:size(s, 1)-1) * (t1_smpls-t0_smpls+1) / max(length(s), 1)) / (signals_fs(kk) / d);
            plot(h_ax{kk}, t, s, 'ButtonDownFcn', @plot_button_down_callback);
            h_ax{kk}.UserData = kk;
            h_ax{kk}.Color = selection_color * selected_axes(kk) + axes_color * (1-selected_axes(kk));
            h_ax{kk}.ButtonDownFcn = @plot_button_down_callback;
            h_ax{kk}.Layer = 'top';
            h_ax{kk}.FontSize = axes_label_font_size;
            h_ax{kk}.TickLength(1) = 0.006;
            if ~signals_positive(kk) && ~signals_negative(kk)
                maxy =  min_abs_signal;
                miny = -min_abs_signal;
            else
                if ~isempty(s)
                    as_ = abs(s(:));
                    maxabs = ylim_margin * (max(as_) + 0.1 * mean(as_));
                    maxabs = max(maxabs, min_abs_signal);
                else
                    maxabs = 1;
                end
                maxy =  maxabs * signals_positive(kk);
                miny = -maxabs * signals_negative(kk);
            end
            h_ax{kk}.XLim = time_range_view;
            if maxy > miny
                h_ax{kk}.YLim = [miny, maxy];
            else
                h_ax{kk}.YLim = [-1, 1];
            end
        end
        highlight_range = tmp_range;
        draw_highlights;
    end

    % Spectrum
    function spectrum_callback(varargin)   % varargin is non-empty if called from menu
        if isgraphics(voctone_h_spec(1))
            % figure already exists, bring to foreground
            figure(voctone_h_spec(1).Number);
        else
            voctone_h_spec(1) = figure;
            if isfield(config, 'spec_Position')
                voctone_h_spec(1).Position = config.spec_Position{1};
            end
        end
        voctone_h_spec(1).CloseRequestFcn = @window_close_callback;
        voctone_h_spec(1).NumberTitle = 'off';
        voctone_h_spec(1).MenuBar = 'none';
        voctone_h_spec(1).ToolBar = 'figure';
        voctone_h_spec(1).Name = ' Vocle Spectrum';
        voctone_h_spec(1).Color = figure_color;
        spectrum_update;
    end

    % compute and display spectra
    function spectrum_update
        if ishandle(voctone_h_spec(1))
            clf(voctone_h_spec(1));
            kk = find(selected_axes);
            if isempty(kk)
                return;
            end
            s = [];
            legend_str = {};
            spec_fs = max(signals_fs(kk));
            for i = 1:length(kk)
                s_ = get_current_signal(kk(i), spec_fs, spec_fs / 20);
                if ~isempty(s_)
                    s = [[s; zeros(size(s_,1)-size(s,1), size(s,2))], ...
                         [s_; zeros(size(s,1)-size(s_,1), size(s_,2))]];
                    switch(size(s_, 2))
                        case 1
                            legend_str{end+1} = ['Signal ', num2str(kk(i))];
                        case 2
                            legend_str{end+1} = ['Signal ', num2str(kk(i)), ', left'];
                            legend_str{end+1} = ['Signal ', num2str(kk(i)), ', right'];
                        otherwise
                            warning(['too many channels for spectrum in signal ', num2str(kk(i))]);
                    end
                end
            end
            if isempty(s)
                return;
            end
            ax_spec = axes('Parent', voctone_h_spec(1));
            if strcmp(get(findall(h_f_scale.Children, 'Label', 'Linear'), 'Checked'), 'on')
                plot_spec_lin(s, spec_fs);
            else
                plot_spec_perc(s, spec_fs);
            end
            ax_spec.FontSize = axes_label_font_size;
            grid(ax_spec, 'on');
            xlabel(ax_spec, 'kHz');
            ylabel(ax_spec, 'dB');
            if length(legend_str) > 1
                legend(ax_spec, legend_str, 'Location', 'best');
            end
        end

        % spectrum on linear scale
        function plot_spec_lin(s, spectrum_fs)
            nfft = 2^nextpow2(max(length(s), spectrum_fs / spectrum_sampling_Hz));
            d = floor(spectrum_sampling_Hz / (spectrum_fs / nfft));
            j = d * round(spectrum_smoothing_Hz / (d * spectrum_fs / nfft));
            w = cos((-j+1:j-1)'/j*pi/2).^2;
            w = w / sum(w);
            fx = abs(fft(s, nfft)).^2;
            fx = [fx(end-j+2:end, :); fx(1:nfft/2+j, :)];
            fxw = zeros(floor(nfft/2/d)+1, size(fx, 2));
            for m = 1:size(fx, 2)
                tmp = conv(fx(:, m), w);
                fxw(:, m) = tmp(2*j-1:d:nfft/2+2*j-1);
            end
            fxw = max(fxw, 1e-100);
            fxw = 10 * log10(fxw);
            f = (0:size(fxw, 1)-1) * d * spectrum_fs / nfft;
            plot(ax_spec, f/1e3, fxw);
            f_ = sort(fxw(:));
            v = f_(ceil(length(f_)/100));  % 1 percentile
            v = max(v, f_(end) - 100);
            axis(ax_spec, [0, spectrum_fs/2e3, v-1, f_(end) + max((f_(end)-v) * 0.05, 1)]);
            h_zoom = zoom(voctone_h_spec(1));
            h_zoom.Enable = 'on';
            h_zoom.ActionPostCallback  = '';
            voctone_h_spec(1).ResizeFcn = @spec_place_axes;
            spec_place_axes;
        end

        % spectrum on perceptual scale
        function plot_spec_perc(s, spectrum_fs)
            nfft = 2^nextpow2(max(length(s), spectrum_fs / spectrum_sampling_Hz));
            fx = abs(fft(s, nfft)).^2;
            f_fft_Hz = (0:nfft-1)' / nfft * spectrum_fs;
            % rotate
            i = find(f_fft_Hz >= spectrum_fs + perc2lin(-spectrum_perc_smoothing), 1);
            fx = [fx(i:end, :); fx(1:i-1, :)];
            f_fft_Hz = [f_fft_Hz(i:end) - spectrum_fs; f_fft_Hz(1:i-1)];
            % remove unused frequencies
            i = f_fft_Hz > perc2lin(lin2perc(spectrum_fs/2) + spectrum_perc_smoothing);
            fx(i, :) = [];
            f_fft_Hz(i) = [];
            % weighting
            [f_fft_p, wght] = lin2perc(f_fft_Hz);
            f_p_end = lin2perc(spectrum_fs/2);
            oversmpl_factor = 6;
            perc_n_smpls = round(oversmpl_factor * f_p_end / spectrum_perc_smoothing);
            f_p_step = f_p_end / (perc_n_smpls - 1);
            f_p = (0:perc_n_smpls-1)' * f_p_step;
            fxw = zeros(perc_n_smpls, size(s, 2));
            pwr = 2;  % make the spectrum for sinusoids less frequency dependent (while keeping white noise flat)
            fx = fx.^pwr;
            for n = 1:perc_n_smpls
                ftmp = f_fft_p - f_p(n);
                i = find(abs(ftmp) < spectrum_perc_smoothing);
                ftmp = ftmp(i);
                w = cos(ftmp / spectrum_perc_smoothing * pi/2).^(2 * pwr);
                w = w .* wght(i);
                w = w / sum(w);
                fxw(n, :) = w' * fx(i, :);
            end
            fxw = fxw.^(1/pwr);
            fxw = max(fxw, 1e-100);
            fxw = 10 * log10(fxw);
            plot(ax_spec, fxw);
            f_ = sort(fxw(:));
            v = f_(ceil(length(f_)/100));  % 1 percentile
            v = max(v, f_(end) - 100);
            axis(ax_spec, [1, perc_n_smpls+1e-9, v-1, f_(end) + max((f_(end)-v) * 0.05, 1)]);
            h_zoom = zoom(voctone_h_spec(1));
            h_zoom.Enable = 'on';
            h_zoom.ActionPostCallback = @spec_set_xticks;
            voctone_h_spec(1).ResizeFcn = @spec_set_xticks;
            spec_set_xticks;

            function spec_set_xticks(varargin)
                if spectrum_fs <= 32000
                    xlabels = [0, 200, 500, 1000, 2000, 4000, 8000, 16000];
                else
                    xlabels = [0, 200, 500, 1000, 2000, 5000, 10000, 20000, 40000];
                end
                xlabels = [xlabels(xlabels < spectrum_fs * 0.4), spectrum_fs/2];
                xtick = 1 + lin2perc(xlabels) / f_p_step;
                ax_spec.XLim(1) = max(ax_spec.XLim(1), 1);
                ax_spec.XLim(2) = min(ax_spec.XLim(2), perc_n_smpls+1e-9);
                ax_spec.Units = 'pixels';
                rat = ax_spec.Position(3) / ax_spec.FontSize;
                ax_spec.Units = 'normalized';
                for m = 1:6
                    nTicks = sum(xtick > ax_spec.XLim(1) & xtick < ax_spec.XLim(2));
                    if 12 * nTicks < rat && nTicks < 6
                        diff = 0.5 * (xlabels(2:end) - xlabels(1:end-1));
                        diff10 = 10.^floor(log10(diff));
                        diff = floor(diff ./ diff10) .* diff10;
                        xlabels = sort([xlabels, xlabels(1:end-1) + diff]);
                    else
                        break;
                    end
                    xtick = 1 + lin2perc(xlabels) / f_p_step;
                end
                ax_spec.XTick = xtick;
                ax_spec.XTickLabel = xlabels / 1e3;
                spec_place_axes;
            end
        end
        
        function spec_place_axes(varargin)
            if isgraphics(voctone_h_spec(1))
                ax_spec.Units = 'pixels';
                h_width = voctone_h_spec(1).Position(3);
                h_height = voctone_h_spec(1).Position(4);
                width = h_width - left_margin - right_margin;
                height = h_height - top_margin - bottom_margin_spec;
                if height > 0 && width > 0
                    ax_spec.Position = [left_margin, bottom_margin_spec, width, height];
                end
                ax_spec.Units = 'normalized';
                write_config;
            end
        end
    end

    % perceptual frequency scale: bandwidth is proportional to f_Hz + spectrum_perc_fc_Hz
    % this means: log scale for frequencies >> spectrum_perc_fc_Hz; linear scale for 
    % frequencies << spectrum_perc_fc_Hz
    function [p, dp] = lin2perc(f_Hz)
        p = log(f_Hz + spectrum_perc_fc_Hz) - log(spectrum_perc_fc_Hz);
        % derivative
        dp = 1 ./ (f_Hz + spectrum_perc_fc_Hz);
    end

    function [f_Hz, df_Hz] = perc2lin(p)
        f_Hz = exp(p + log(spectrum_perc_fc_Hz)) - spectrum_perc_fc_Hz;
        % derivative
        df_Hz = f_Hz + spectrum_perc_fc_Hz;
    end

    % Spectrogram
    function spectrogram_callback(varargin)   % varargin is non-empty if called from menu
        % see if any spectrogram windows are open
        specgram_open = any(isgraphics(voctone_h_spec(1+(1:num_signals))));
        if isempty(varargin) && ~specgram_open
            return;
        end
        kk = find(selected_axes);
        ax = gobjects(length(kk), 1);
        for i = 1:length(kk)
            if isgraphics(voctone_h_spec(i+1))
                % figure already exists
                if ~isempty(varargin)
                    % bring to foreground
                    figure(voctone_h_spec(i+1).Number);
                end
            else
                voctone_h_spec(i+1) = figure;
                if isfield(config, 'spec_Position') && length(config.spec_Position) >= i+1
                    voctone_h_spec(i+1).Position = config.spec_Position{i+1};
                end
            end
            voctone_h_spec(i+1).CloseRequestFcn = @window_close_callback;
            voctone_h_spec(i+1).NumberTitle = 'off';
            voctone_h_spec(i+1).MenuBar = 'none';
            voctone_h_spec(i+1).ToolBar = 'figure';
            voctone_h_spec(i+1).Name = [' Vocle Spectrogram - Signal ', num2str(kk(i))];
            voctone_h_spec(i+1).Color = figure_color;
            clf(voctone_h_spec(i+1));
            h_zoom = zoom(voctone_h_spec(i+1));
            h_zoom.Enable = 'on';
            h_zoom.ActionPostCallback  = '';
            voctone_h_spec(i+1).ResizeFcn = @specgram_place_axes;

            ax(i) = axes('Parent', voctone_h_spec(i+1));
            win_len_ms = sscanf(get(findall(h_sg_win.Children, 'Checked', 'on'), 'Label'), '%d ms');
            step_ms = min(win_len_ms/20, 1) ;
            spec_fs = max(signals_fs(kk));
            [s, time_range] = get_current_signal(kk(i), spec_fs, 0, win_len_ms / 2);
            % take average between all channels (for now..)
            s = mean(s, 2);
            win_len = win_len_ms * spec_fs / 1e3;
            step = step_ms * spec_fs / 1e3;
            N = ceil((length(s) - win_len + 1) / step);
            if N > 0
                U = 10;
                s_up = resample(s, U, 1, 30);
                nfft = 2^nextpow2(win_len * 3);
                F = zeros(nfft/2+1, N);
                % frequency modulation values
                if win_len_ms > 10
                    dmm = 4;
                    mm = ( -round(min(0.25 * win_len_ms, 40) / dmm) : round(min(0.6 * win_len_ms, 60) / dmm) ) * dmm;
                else
                    mm = 0;
                end
                smpl_step = (1:win_len-1)' / win_len * 0.01;
                smpl_step = smpl_step - mean(smpl_step);
                dt = smpl_step * (mm * U);
                tw = bsxfun(@plus, (0:win_len-1)' * U + 1, [dt(1, :) * 0; cumsum(dt)]);
                t_int = floor(tw);
                t_frac = tw - t_int;
                win = sin((0.5:win_len)' / win_len * pi) .^ 2;
                win = bsxfun(@times, (1 + [dt(1, :); dt]).^0.5, win);
                for n = 1:N
                    % for each frame, resample signal with different linear frequency shifts and
                    % compute FFT for each resampled signal. then measure sparseness for each 
                    % spectrum, and blend magnitude spectra with weights proportional to sparseness
                    si = s_up(t_int) + (s_up(t_int+1) - s_up(t_int)) .* t_frac;
                    t_int = t_int + step * U;
                    f = fft(si .* win, nfft);
                    f = abs(f(1:nfft/2+1, :));
                    % sparseness measure
                    r = mean(f) ./ sqrt(mean(f.^2));
                    % weights
                    r = min(r) - r;
                    w = exp(200 * r - abs(mm) * 0.5);
                    w = w / sum(w);
                    F(:, n) = f * w';
                end
                F = max(F, 1e-5 * max(F(:)));
                F = 20 * log10(F);
                t = time_range(1) + win_len_ms/2e3 + (-0.5:N) * step_ms/1e3;
                fr = (-0.5:nfft/2+1)/nfft * spec_fs;
                F = [F; F(end, :)];
                F = [F, F(:, end)];
                pcolor(ax(i), t, fr/1e3, F);
                ax(i).XLim = [t(1), t(end)];
                ylabel(ax(i), 'kHz');
                shading(ax(i), 'flat');
                colormap(ax(i), 'default')
                c = colorbar(ax(i));
                c.Label.String = 'dB';
                ax(i).FontSize = axes_label_font_size;
                specgram_place_axes(voctone_h_spec(i+1));
            end
        end
        if exist('ax', 'var')
            ax(~isgraphics(ax)) = [];
            if length(ax) > 1
                try
                    linkaxes(ax);
                catch
                end
            end
        end
        for i = length(kk)+1:num_signals
            if isgraphics(voctone_h_spec(i+1))
                close(voctone_h_spec(i+1));
            end
        end
        % bring main window back to foreground, unless called from menu
        if isempty(varargin)
            figure(voctone_h_fig);
        end
    end

    function specgram_place_axes(varargin)
        if nargin > 1
            % to handle a bug in colorbar position when resizing a spectrogram 
            % window, wait for matlab to update layout first
            pause(0.5);
        end
        hf = varargin{1};
        h_width = hf.Position(3);
        h_height = hf.Position(4);
        ax = findall(hf.Children, 'Type', 'Axes');
        ax.Units = 'pixels';
        width = h_width - left_margin - right_margin - 45;
        height = h_height - top_margin - vert_spacing;
        if height > 0 && width > 0
            ax.Position = [left_margin, vert_spacing, width, height];
            c = findall(hf.Children, 'Type', 'ColorBar');
            if ~isempty(c)
                c.Units = 'pixels';
                c.Position = [h_width - 53, vert_spacing, 15, height];
                c.Units = 'normalized';
            end
        end
        ax.Units = 'normalized';
        write_config;
    end

    function [s, time_range] = get_current_signal(kk, fs_out, win_len_smpls, extra_ms)
        if nargin < 4
            extra_ms = 0;
        end
        s = signals{kk};
        if ~isempty(highlight_range) && abs(diff(highlight_range)) > 0
            t0 = min(highlight_range);
            t1 = max(highlight_range);
        else
            t0 = time_range_view(1);
            t1 = time_range_view(2);
        end
        t0 = t0 - extra_ms / 1e3;
        t1 = t1 + extra_ms / 1e3;
        t0 = max(round(t0 * signals_fs(kk)), 1);
        t1 = min(round(t1 * signals_fs(kk)), signal_lengths(kk));
        time_range = [t0, t1] / signals_fs(kk);
        s = double(s(t0:t1, :));
        if fs_out ~= signals_fs(kk)
            s = resample(s, fs_out, signals_fs(kk), 100);
        end
        % windowing
        if win_len_smpls > 0
            smpls = size(s, 1);
            fade_smpls = min(win_len_smpls, smpls / 2);
            win = sin((1:fade_smpls)' / (fade_smpls+1) * pi/2) .^ 2;
            t = 1:fade_smpls;
            s(t, :) = bsxfun(@times, s(t, :), win);
            s(end-t+1, :) = bsxfun(@times, s(end-t+1, :), win);
        end
    end

    function start_play(varargin)
        % stop any ongoing playback before starting a new one
        if ~isempty(player)
            player.StopFcn = '';  % prevent that stop_play resets play_src
            stop(player);
            for m = 1:length(play_cursors)
                delete(play_cursors{m});
            end
            play_cursors = {};
        end
        play_src = find(selected_axes);
        if strcmp(play_button.Enable, 'off')
            return;
        end
        play_button.String = 'Stop';
        play_button.Enable = 'on';
        play_button.Callback = @stop_play;
        if length(play_src) == 1
            % playback from a single axes
            [s, play_time_range] = get_current_signal(play_src, playback_fs, playback_fs / 100);
            if isempty(s)
                return;
            end
            s = s / signals_max(play_src) * 10^(0.05 * playback_dBov);
        elseif length(play_src) == 2
            % A/B test
            rng('shuffle'); 
            play_src = play_src(randperm(2));
            s = {};
            play_time_range = 0;
            for i = 1:2
                [s{i}, tr] = get_current_signal(play_src(i), playback_fs, playback_fs / 100);
                if isempty(s{i})
                    return;
                end
                play_time_range = play_time_range + tr / 2;
                s{i} = s{i} / signals_max(play_src(i)) * 10^(0.05*playback_dBov);
                s{i} = repmat(s{i}, [1, 3 - size(s{i}, 2)]);  % always stereo
            end
            s = [s{1}; zeros(round(playback_fs/1e3 * playback_silence_between_A_B_ms), 2); s{2}]; 
        end
        player = audioplayer(s, playback_fs, playback_bits);
        player.TimerFcn = @draw_play_cursors;
        player.TimerPeriod = 0.05;
        playback_start_time = tic;
        draw_play_cursors;
        player.StopFcn = @stop_play;
        play(player);
        
        function stop_play(varargin)
            stop(player);
            for mm = 1:length(play_cursors)
                delete(play_cursors{mm});
            end
            play_cursors = {};
            play_button.Callback = @start_play;
            if length(play_src) == 2
                if play_src(1) > play_src(2)
                    disp('Playout order: bottom, top');
                else
                    disp('Playout order: top, bottom');
                end
            end
            update_play_button;
        end

        function draw_play_cursors(~, ~)
            t = play_time_range(1) + toc(playback_start_time) - playback_cursor_delay_ms / 1e3;
            if length(play_src) == 2 && t > play_time_range(2) + 0.5 * playback_silence_between_A_B_ms/1e3
                t = t - diff(play_time_range) - playback_silence_between_A_B_ms/1e3;
            end
            t = min(max(t, play_time_range(1)), play_time_range(2));
            for mm = 1:length(play_cursors)
                delete(play_cursors{mm});
            end
            for mm = 1:length(play_src)
                play_cursors{mm} = line([1, 1] * t, 2 * h_ax{play_src(mm)}.YLim, ...
                   'Parent', h_ax{play_src(mm)}, 'Color', 'k', 'HitTest', 'off');
            end
        end
    end
        
    function t = get_mouse_pointer_time
        frac = (voctone_h_fig.CurrentPoint(1) - left_margin) / max(voctone_h_fig.Position(3) - left_margin - right_margin, 1);
        t = time_range_view(1) + frac * diff(time_range_view);
    end

    function zoom_axes(factor)
        % factor > 1: zoom out; factor < 1: zoom in
        % keep time under mouse constant
        tmouse = get_mouse_pointer_time;
        tmouse = min(max(tmouse, time_range_view(1)), time_range_view(2));
        t0 = tmouse - (tmouse - time_range_view(1)) * factor;
        interval = diff(time_range_view) * factor;
        t0 = max(t0, 0);
        t1 = t0 + interval;
        t1 = min(t1, max(signal_lengths ./ signals_fs));
        set_time_range([t1 - interval, t1], 1);
    end

    % update visible time range
    function set_time_range(range, update_slider)
        min_delta = max_zoom_smpls / config.fs;
        max_time = max(signal_lengths ./ signals_fs);
        if range(1) < 0
            range = range - range(1);
        end
        if range(2) > max_time
            range = range - (range(2) - max_time);
        end
        time_range_view(1) = min(max(range(1), 0), max_time - min_delta);
        time_range_view(2) = max(min(range(2), max_time), 0 + min_delta);
        time_range_view = time_range_view + max(min_delta - diff(time_range_view), 0) * [-0.5, 0.5];
        % update signals
        plot_signals;
        % update slider
        if update_slider
            time_diff = diff(time_range_view);
            val = (mean(time_range_view) - time_diff / 2 + 1e-6) / (max_time - time_diff + 2e-6);
            slider_listener.Enabled = 0;
            time_slider.Value = min(max(val, 0), 1);
            slider_listener.Enabled = 1;
            frac_time = min(time_diff / max_time, 1);
            if 1
                % zooming out fully, the slider should take up the entire width; it doesn't
                time_slider.SliderStep = [0.1, 1] * frac_time;
            else
                % this fixes the width problem of the slider, but doesn't work
                % reliably: sometimes the slider is in the wrong position
                time_slider.SliderStep = [0.1, 1 / (1.0001 - frac_time)] * frac_time;
            end
        end
    end

    function delete_highlights
        for kk = 1:num_signals
            if ~isempty(highlight_patches{kk})
                delete(highlight_patches{kk});
                highlight_patches{kk} = [];
            end
        end
        highlight_range = [];
    end

    function draw_highlights
        if ~isempty(highlight_range)
            for kk = 1:num_signals
                if isempty(highlight_patches{kk})
                    highlight_patches{kk} = patch(highlight_range([1, 2, 2, 1]), ...
                        2 * kron(h_ax{kk}.YLim, [1, 1]), highlight_color, 'Parent', h_ax{kk}, ...
                        'EdgeColor', marker_color, 'LineWidth', 0.3, 'FaceAlpha', 0.25, 'HitTest', 'off');
                    uistack(highlight_patches{kk}, 'bottom');
                else
                    highlight_patches{kk}.Vertices(:, 1) = highlight_range([1, 2, 2, 1]);
                end
            end
        end
    end

    function plot_button_down_callback(~, ~)
        if strcmp(voctone_h_fig.SelectionType, 'normal')
            kk = get(gca, 'UserData');
            t = get_mouse_pointer_time * signals_fs(kk);
            % linearly interpolate
            yval = ([1, 0] + [-1, 1] * (t - floor(t))) * double(signals{kk}(floor(t) + [0; 1], :));
            text_segment.String = num2str(yval, ' %.3g');
            text_segment.Visible = 'on';
            % the function called next will set text_segment.Position
        end
        % pass through to next function
        axes_button_down_callback(gca, []);
    end

    last_action_was_highlight = 0;
    last_button_down = '';
    function axes_button_down_callback(src, ~)
        n_axes = src.UserData;
        if verbose
            disp(['mouse click on axes ', num2str(n_axes), ', type: ' voctone_h_fig.SelectionType, ...
                ', previous: ', last_button_down, ', modifier: ' cell2mat(voctone_h_fig.CurrentModifier)]);
        end
        % deal with different types of mouse clicks
        switch(voctone_h_fig.SelectionType)
            case 'normal'
                % left mouse: start highlight, move indicator to current axes, setup mouse callbacks
                time_mouse_down = tic;
                highlight_start = get_mouse_pointer_time;
                text_segment.Position = [src.Position(1)+ 3, sum(src.Position([2, 4])) - 17, 100, 14];
                voctone_h_fig.WindowButtonUpFcn = @button_up_callback;
                voctone_h_fig.WindowButtonMotionFcn = @button_motion_callback;
                for kk = 1:num_signals
                    highlight_markers{kk} = line([1, 1] * highlight_start, 2 * h_ax{kk}.YLim, ...
                        'Parent', h_ax{kk}, 'Color', marker_color, 'HitTest', 'off');
                end
            case 'alt'
                % right mouse
                if isempty(highlight_range) || diff(highlight_range) == 0
                    % zoom out 2x
                    zoom_axes(2);
                else
                    % zoom to segment
                    set_time_range(sort(highlight_range), 1);
                    delete_highlights;
                end
            case 'extend'
                % Shift + left mouse
                start_play;
            case 'open'
                % double click
                switch(last_button_down)
                    case 'normal'
                        % double click left: zoom out full
                        set_time_range([0, inf], 1);
                    case 'alt'
                        % right mouse: zoom out 2x
                        zoom_axes(2);
                    case 'extend'
                        % Shift + double click
                        start_play;
                end
        end
        if ~strcmp(voctone_h_fig.SelectionType, 'open')
            last_button_down = voctone_h_fig.SelectionType;
        end

        function button_up_callback(~, ~)
            voctone_h_fig.WindowButtonUpFcn = '';
            voctone_h_fig.WindowButtonMotionFcn = '';
            text_segment.Visible = 'off';
            if last_action_was_highlight
                spectrum_update;
                spectrogram_callback;
            else
                for kkk = 1:num_signals
                    delete(highlight_markers{kkk});
                end
                if toc(time_mouse_down) < 0.4
                    update_axes_selections(n_axes, 'toggle');
                    update_play_button;
                    if diff(highlight_range)
                        spectrum_update;
                        spectrogram_callback;
                    end
                end
            end
            last_action_was_highlight = 0;
        end

        function button_motion_callback(~, ~)
            highlight_cur = get_mouse_pointer_time;
            highlight_range_prelim = [highlight_start, highlight_cur];
            delta = abs(diff(highlight_range_prelim));
            % ignore short, tiny "selections"; they're most likely just clicks
            if delta < min_selection_frac * diff(time_range_view) && toc(time_mouse_down) < 0.25
                return;
            end
            highlight_range = highlight_range_prelim;
            if delta < 1
                kk = get(gca, 'UserData');
                smpls = delta * signals_fs(kk);
                if smpls < 1000
                    str = [num2str(delta * 1e3, '%.3g'), ' ms (', num2str(smpls, '%.1f'), ')'];
                else
                    str = [num2str(delta * 1e3, '%.3g'), ' ms (', num2str(smpls, '%.0f'), ')'];
                end
            elseif delta < 100
                str = [num2str(delta, '%.3f'), ' sec'];
            else
                str = [num2str(delta, '%.0f'), ' sec'];
            end
            text_segment.String = str;
            text_segment.Visible = 'on';
            draw_highlights;
            last_action_was_highlight = 1;
            for kkk = 1:num_signals
                delete(highlight_markers{kkk});
            end
        end
    end

    signal_prev = [];
    function keypress_callback(~, evt)
        if isempty(evt.Character) 
            return; 
        end
        % overwrite selection by a value of 0, 1, 2, ... 9
        if evt.Character >= '0' && evt.Character <= '9' && enable_edit_mode
            kk = find(selected_axes);
            if length(kk) ~= 1
                return;
            end
            if isempty(highlight_range) || abs(diff(highlight_range)) == 0
                return;
            end
            t0 = min(highlight_range);
            t1 = max(highlight_range);
            t0_smpls = max(round(t0 * signals_fs(kk)), 1);
            t1_smpls = min(round(t1 * signals_fs(kk)), signal_lengths(kk));
            val = single(str2double(evt.Character));
            signal_prev.kk = kk;
            signal_prev.signal = {};
            for m = 1:size(signals, 2)
                signal_prev.signal{m} = signals{kk, m};
                if isempty(signals{kk, m})
                    break;
                end
                signals{kk, m}(t0_smpls:t1_smpls) = val;
                t0_smpls = ceil(t0_smpls/4);
                t1_smpls = floor(t1_smpls/4);
            end
            plot_signals;
        end
        % Ctrl-z: restore previous version of signal
        if strcmp(evt.Key, 'z') && ...
                ~isempty(evt.Modifier) && strcmp(evt.Modifier, 'control') && ...
                ~isempty(signal_prev)
            for m = 1:size(signals, 2)
                signals{signal_prev.kk, m} = signal_prev.signal{m};
            end
            plot_signals;
        end
        % Space: start/stop playback
        if strcmp(evt.Key, 'space')
            feval(play_button.Callback);
        end
        % Arrows: scroll horizontally
        if strcmp(evt.Key, 'rightarrow')
            set_time_range(time_range_view + 0.4 * diff(time_range_view), 1);
        end
        if strcmp(evt.Key, 'leftarrow')
            set_time_range(time_range_view - 0.4 * diff(time_range_view), 1);
        end
    end

    function window_scroll_callback(~, evt)
        zoom_axes(zoom_per_scroll_wheel_step ^ evt.VerticalScrollCount);
    end

    function slider_moved_callback(~, ~)
        time_diff = diff(time_range_view);
        time_center = 0.5 * time_diff + time_slider.Value * (max(signal_lengths ./ signals_fs) - time_diff);
        set_time_range(time_center + time_diff * [-0.5, 0.5], 0);
    end

    function window_button_down_callback(~, ~)
        % mouse click outside axes
        delete_highlights;
        highlight_range = [];
    end

    function change_fs_callback(src, ~)
        fs_old = config.fs;
        config.fs = str2double(src.Label);
        set(findall(h_fs.Children, 'Checked', 'on'), 'Checked', 'off');
        src.Checked = 'on';
        write_config;
        signals_fs = signals_fs * config.fs / fs_old;
        highlight_range = highlight_range * fs_old / config.fs;
        set_time_range(time_range_view * fs_old / config.fs, 1);
        spectrum_update;
        spectrogram_callback;
    end

    function change_spectrogram_win_callback(src, ~)
        set(findall(h_sg_win.Children, 'Checked', 'on'), 'Checked', 'off');
        src.Checked = 'on';
        spectrogram_callback(1);
        write_config;
    end

    function spec_scale_callback(src, ~)
        set(findall(h_f_scale.Children, 'Checked', 'on'), 'Checked', 'off');
        src.Checked = 'on';
        spectrum_callback;
        write_config;
    end

    function window_resize_callback(~, ~)
        update_layout;
        write_config;
    end

    function window_close_callback(~, ~)
        write_config;
        closereq;
    end

    function window_close_all_callback(src, ~)
        write_config;
        close(voctone_h_spec(isgraphics(voctone_h_spec)));
        if src == voctone_h_fig
            closereq;
        end
    end

    function write_config
        if verbose
            disp('save config');
        end
        if isgraphics(voctone_h_fig)
            config.Position = voctone_h_fig.Position;
        end
        if ishandle(h_sg_win)
            config.specgram_win = get(findall(h_sg_win.Children, 'Checked', 'on'), 'Label');
        end
        if ishandle(h_f_scale)
            config.spectrum_scale = get(findall(h_f_scale.Children, 'Checked', 'on'), 'Label');
        end
        for i = 1:length(voctone_h_spec)
            if ishandle(voctone_h_spec(i))
                config.spec_Position{i} = voctone_h_spec(i).Position;
            end
        end
        save(config_file, 'config');
    end
end
