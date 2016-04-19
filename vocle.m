function vocle(varargin)
% Audio navigator
%
% Usage:
% 
% Vocle is inspired by Thomas Eriksson's spclab, and shares some interaction behavior. 
% Some advantages over spclab:
% - A/B test
% - Stereo support
% - Possible to stop playback
% - Scroll wheel zooming
% - Remember configuration such as window location and sampling rate between calls to vocle

% todo:
% - play cursor timing
% - help section
% - spectrogram
% - option to show spectrum on a perceptual frequency scale?
%   --> do smoothing on warped scale
% - remember selection, zoom and highlight if main window was already open?
% - "keep" option to store a signal and add it to the next call to vocle?
%   --> show in a different color
%   --> option to remove signals
% - auto align function?
% - Info menu item
%
% Copyright Koen Vos, 2016

% settings
fig_no = 9372;
spectrum_no = fig_no+1;
config_file = [which('vocle'), 'at'];
axes_label_font_size = 8;
% space around and between axes
left_margin = 42;
right_margin = 22;
bottom_margin = 84;
top_margin = 13;
vert_spacing = 30;
slider_height = 16;
figure_color = [0.92, 0.92, 0.92];
selection_color = [0.95, 0.95, 0.95];
highlight_color = [0.7, 0.8, 0.9];
zoom_per_scroll_wheel_step = 1.4;
ylim_margin = 1.1;
file_fs = [192000, 96000, 48000, 44100, 32000, 16000, 8000];
default_fs = 48000;
playback_fs = 48000;
playback_bits = 24;
playback_dBov = -2;
playback_cursor_delay_ms = 100;
spectrum_sampling_Hz = 2;
spectrum_smoothing_Hz = 20;
verbose = 0;

% function-wide variables
h_ax = [];
h_spectrum = [];
selected_axes = [];
time_range_view = [];
highlight_range = [];
play_cursor = [];
player = [];
play_src = [];
play_time_range = [];
playback_start_time = [];

% load configuration, if possible
config = [];
if exist(config_file, 'file')
    load(config_file);
end

% open figure and use position from config file
if ~fig_exist(fig_no) && isfield(config, 'Position')
    h_fig = figure(fig_no);
    h_fig.Position = config.Position;
else
    h_fig = figure(fig_no);
end
clf;
h_fig.NumberTitle = 'off';
h_fig.Name = ' Vocle';
h_fig.Color = figure_color;
h_fig.ToolBar = 'none';
h_fig.MenuBar = 'none';
h_file = uimenu(h_fig, 'Label', '&File');
uimenu(h_file, 'Label', '&Open', 'Callback', @open_file_callback);
h_save = uimenu(h_file, 'Label', 'Save &As..', 'Callback', @save_file_callback);
h_spec_menu = uimenu(h_fig, 'Label', '&Spectrum', 'Callback', @spectrum_callback);
h_specgram_menu = uimenu(h_fig, 'Label', 'Spectro&gram', 'Callback', @spectrogram_callback);
h_specgram_menu.Enable = 'off';
h_fs = uimenu(h_fig, 'Label', 'Sampling &Rate');
for k = 1:length(file_fs)
    uimenu(h_fs, 'Label', num2str(file_fs(k)), 'Callback', @change_fs_callback);
end

% process inputs
% check if first argument is sampling rate, otherwise use the config value
first_arg_fs = 0;
if ~isempty(varargin) && isscalar(varargin{1}) && isnumeric(varargin{1})
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
signals_ylim = zeros(num_signals, 1);
file_fs = zeros(num_signals, 1);
for k = 1:num_signals
    arg = varargin{k+first_arg_fs};
    if ischar(arg)
        % file name
        if ~exist(arg, 'file')
            error(['  file not found: ', varargin{k}]);
        else
            try
                [signals{k}, file_fs(k)] = audioread(arg);
            catch
                % read as shorts without header
                fid = fopen(arg, 'rb');
                signals{k} = fread(fid, inf, 'short') / 32768;
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
if sum(file_fs)
    config.fs = max(max(file_fs), first_arg_fs * config.fs);
end
set(findall(h_fs.Children, 'Label', num2str(config.fs)), 'Checked', 'on');
write_config;
for k = 1:num_signals
    if file_fs(k)
        % upsample to highest sampling rate
        signals{k} = resample(signals{k}, config.fs, file_fs(k));
    elseif first_arg_fs
        signals{k} = resample(signals{k}, config.fs, varargin{1});
    end
    signal_lengths(k) = size(signals{k}, 1);
    s_ = signals{k}(:);
    signals_negative(k) = min(s_) < 0;
    signals_ylim(k) = ylim_margin * max(abs(s_));
end

% put elements on UI
h_ax = cell(num_signals, 1);
for k = 1:num_signals
    h_ax{k} = axes;
    h_ax{k}.Units = 'pixels';
end
text_segment = uicontrol(h_fig, 'Style', 'text', 'FontName', 'Helvetica', ...
    'BackgroundColor', [1, 1, 1], 'Visible', 'off', 'HitTest', 'Off');
time_slider = uicontrol(h_fig, 'Style', 'slider', 'Value', 0.5, 'BackgroundColor', selection_color);
slider_listener = addlistener(time_slider, 'Value', 'PostSet', @slider_moved_callback);
play_button = uicontrol(h_fig, 'Style', 'pushbutton', 'String', 'Play', 'FontSize', 9, 'Callback', @start_play);
update_layout;

% show signals
update_selections([], 'reset');
set_time_range([0, inf], 1);

% set figure callbacks
h_fig.CloseRequestFcn = @window_close_callback;
h_fig.SizeChangedFcn = @window_resize_callback;
h_fig.ButtonDownFcn = @window_button_down_callback;
h_fig.WindowScrollWheelFcn = @window_scroll_callback;
h_fig.WindowButtonUpFcn = '';

    % position UI elements
    function update_layout
        h_width = h_fig.Position(3);
        h_height = h_fig.Position(4);
        width = h_width - left_margin - right_margin;
        height = (h_height - top_margin - bottom_margin - (num_signals-1) * vert_spacing) / num_signals;
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
            for kk = 1:length(file_names)-1
                 str = [str, '''', path_name file_names{kk}, ''', '];
            end
            str = [str, '''', path_name file_names{end}, ''');'];
        else
            str = [str, '''', path_name file_names, ''');'];
        end
        eval(str);
    end

    function save_file_callback(~, ~)
        if diff(highlight_range)
            title_str = 'Save highlighted segment';
        else
            title_str = 'Save selected signal';
        end
        file_types = {'*.wav'; '*.m4a'; '*.mat'};
        [file_name, path_name, file_type_ix] = uiputfile(file_types, title_str, 'signal.wav');
        if ischar(path_name) && ischar(file_name)
            kk = find(selected_axes);  % must be of length 1
            signal = get_current_signal(kk, 0);
            if file_type_ix ~= length(file_types)
                % audio file
                audiowrite([path_name, file_name], signal, config.fs);
            else
                % MAT file
                save([path_name, file_name], 'signal');
            end
        end
    end

    function update_selections(ind, type)
        if num_signals == 1
            selected_axes = 1;
        else
            switch(type)
                case {'unique', 'reset'}
                    selected_axes = zeros(num_signals, 1);
                    selected_axes(ind) = 1;
                case 'add'
                    selected_axes(ind) = 1;
                case 'toggle'
                    selected_axes(ind) = 1 - selected_axes(ind);
            end
        end
        for kk = 1:num_signals
            h_ax{kk}.Color = selection_color.^(1-selected_axes(kk));
        end
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
        if sum(selected_axes) == 0
            h_spec_menu.Enable = 'off';
        else
            h_spec_menu.Enable = 'on';
        end
        if sum(selected_axes) == 1
            h_save.Enable = 'on';
        else
            h_save.Enable = 'off';
        end
        if diff(highlight_range)
            spectrum_update;
        end
    end

    % plot signals
    function plot_signals
        tmp_range = highlight_range;
        delete_highlights;   % they wouldn't survive the plotting
        for kk = 1:num_signals
            t0 = max(floor(time_range_view(1)*config.fs), 1);
            t1 = min(ceil(time_range_view(2)*config.fs), signal_lengths(kk));
            s = signals{kk};
            s_ = reduce(s(t0:t1, :));
            t = (t0 + (0:size(s_, 1)-1) * (t1-t0+1) / length(s_)) / config.fs;
            plot(h_ax{kk}, t, s_, 'ButtonDownFcn', @plot_button_down_callback);
            h_ax{kk}.UserData = kk;
            h_ax{kk}.Color = selection_color.^(1-selected_axes(kk));
            h_ax{kk}.ButtonDownFcn = @axes_button_down_callback;
            h_ax{kk}.Layer = 'top';
            h_ax{kk}.FontSize = axes_label_font_size;
            if ~isempty(s_)
                maxy = 1.1 * max(abs(s_(:)));
                maxy = max(maxy, 1e-9);
            else
                maxy = 1;
            end
            miny = -maxy * signals_negative(kk);
            h_ax{kk}.XLim = time_range_view;
            h_ax{kk}.YLim = [miny, maxy];
        end
        highlight_range = tmp_range;
        draw_highlights;
    end

    function spectrum_callback(varargin)
        % open figure and use position from config file
        if ~fig_exist(spectrum_no) && isfield(config, 'spectrum_Position')
            h_spectrum = figure(spectrum_no);
            h_spectrum.Position = config.spectrum_Position;
        else
            h_spectrum = figure(spectrum_no);
        end
        h_spectrum.CloseRequestFcn = @window_close_callback;
        h_spectrum.NumberTitle = 'off';
        h_spectrum.MenuBar = 'none';
        h_spectrum.ToolBar = 'figure';
        h_spectrum.Name = ' Vocle Spectrum';
        h_spectrum.Color = figure_color;
        spectrum_update;
    end

    % compute and display spectra
    function spectrum_update
        if ishandle(h_spectrum)
            clf(h_spectrum);
            kk = find(selected_axes);
            if isempty(kk)
                return;
            end
            s = [];
            legend_str = {};
            for i = 1:length(kk)
                s_ = get_current_signal(kk(i), config.fs / 20);
                if ~isempty(s_)
                    s = [[s; zeros(size(s_,1)-size(s,1), size(s,2))], [s_; zeros(size(s,1)-size(s_,1), size(s_,2))]];
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
            nfft = 2^nextpow2(max(length(s), config.fs / spectrum_sampling_Hz));
            d = floor(spectrum_sampling_Hz / (config.fs / nfft));
            j = d * round(spectrum_smoothing_Hz / (d * config.fs / nfft));
            w = cos((-j+1:j-1)'/j*pi/2).^2;
            w = w / sum(w);
            fx = abs(fft(s, nfft)).^2;
            % circular convolution
            fx = ifft(bsxfun(@times, fft(fx), fft(w, nfft)));
            fx = fx(j:d:nfft/2+j, :);
            fx = max(fx, 1e-100);
            fx = 10*log10(fx);
            f = (0:size(fx, 1)-1) * d * config.fs / nfft;
            f_ = sort(fx(:));
            v = f_(ceil(length(f_)/200));  % 0.5 percentile
            ax = axes('Parent', h_spectrum);
            plot(ax, f/1e3, fx);
            axis(ax, [0, config.fs/2e3, v-1, f_(end) + max((f_(end)-v) * 0.05, 1)]);
            ax.Position = [0.1, 0.13, 0.87, 0.84];
            xlabel(ax, 'kHz');
            ylabel(ax, 'dB');
            ax.FontSize = 9;
            grid(ax, 'on');
            zoom(h_spectrum, 'on');
            if length(legend_str) > 1
                legend(ax, legend_str, 'Location', 'best');
            end
        end
    end

    function spectrogram_callback(varargin)
        disp('spectrogram is not yet implemented..');
    end

    function [s, time_range] = get_current_signal(kk, win_len)
        s = signals{kk};
        if ~isempty(highlight_range) && abs(diff(highlight_range)) > 0
            t0 = min(highlight_range);
            t1 = max(highlight_range);
        else
            t0 = time_range_view(1);
            t1 = time_range_view(2);
        end
        t0 = max(round(t0 * config.fs), 1);
        t1 = min(round(t1 * config.fs), signal_lengths(kk));
        s = s(t0:t1, :);
        smpls = size(s, 1);
        if win_len > 0
            % windowing
            fade_smpls = min(win_len, smpls / 2);
            win = sin((1:fade_smpls)'/(fade_smpls+1)*pi/2) .^ 2;
            t = 1:fade_smpls;
            s(t, :) = bsxfun(@times, s(t, :), win);
            s(end-t+1, :) = bsxfun(@times, s(end-t+1, :), win);
        end
        time_range = [t0, t1] / config.fs;
    end

    function start_play(varargin)
        % stop any ongoing playback before starting a new one
        if ~isempty(player)
            player.StopFcn = '';  % prevent that stop_play resets play_src
            stop(player);
            delete(play_cursor);
        end
        if isempty(play_src)
            play_src = find(selected_axes);
        end
        play_button.String = 'Stop';
        play_button.Enable = 'on';
        play_button.Callback = @stop_play;
        if length(play_src) == 1
            % playback from a single axes
            [s, play_time_range] = get_current_signal(play_src, config.fs / 100);
            s = s / (signals_ylim(play_src) / ylim_margin) * 10^(0.05*playback_dBov);
            s = resample(s, playback_fs, config.fs, 50);
            player = audioplayer(s, playback_fs, playback_bits);
            player.TimerFcn = @draw_play_cursor;
            player.TimerPeriod = 0.02;
            player.StopFcn = @stop_play;
            play_cursor = line([1, 1] * play_time_range(1), [-1, 1] * signals_ylim(play_src), ...
                'Parent', h_ax{play_src}, 'Color', 'k', 'HitTest', 'off');
            playback_start_time = tic;
            play(player);
        elseif length(play_src) == 2
            % A/B test
            play_src = play_src(randperm(2));
            ss = [];
            for i = 1:2
                s = get_current_signal(play_src(i), config.fs / 100);
                s = s / (signals_ylim(play_src(i)) / ylim_margin) * 10^(0.05*playback_dBov);
                ss = [ss; repmat(s, [1, 3 - size(s, 2)])];  % always stereo
            end
            ss = resample(ss, playback_fs, config.fs, 50);
            player = audioplayer(ss, playback_fs, playback_bits);
            player.StopFcn = @stop_play;
            play(player);
        end
    end
        
    function stop_play(varargin)
        stop(player);
        delete(play_cursor);
        play_button.Callback = @start_play;
        if length(play_src) == 2
            if play_src(1) > play_src(2)
                disp('Playout order: bottom, top');
            else
                disp('Playout order: top, bottom');
            end
        end
        play_src = [];
        update_selections([], '');
    end

    function draw_play_cursor(~, ~)
        t = play_time_range(1) + toc(playback_start_time) - playback_cursor_delay_ms / 1e3;
        t = min(max(t, play_time_range(1)), play_time_range(2));
        delete(play_cursor);
        play_cursor = line([1, 1] * t, [-1, 1] * signals_ylim(play_src), ...
            'Parent', h_ax{play_src}, 'Color', 'k', 'HitTest', 'off');
    end

    function t = get_mouse_pointer_time
        frac = (h_fig.CurrentPoint(1) - left_margin) / (h_fig.Position(3) - left_margin - right_margin);
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
        t1 = min(t1, max(signal_lengths) / config.fs);
        set_time_range([t1 - interval, t1], 1);
    end

    % update axis
    function set_time_range(range, update_slider)
        min_delta = 10 / config.fs;
        max_time = max(signal_lengths) / config.fs;
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
            frac_time = time_diff / max_time;
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
                    highlight_patches{kk} = patch(highlight_range([1, 2, 2, 1]), signals_ylim(kk) * [-1, -1, 1, 1], ...
                        highlight_color, 'Parent', h_ax{kk}, 'LineStyle', 'none', 'FaceAlpha', 0.4, 'HitTest', 'off');
                    uistack(highlight_patches{kk}, 'bottom');
                else
                    highlight_patches{kk}.Vertices(:, 1) = highlight_range([1, 2, 2, 1]);
                end
            end
        end
    end

    function plot_button_down_callback(~, ~)
        if strcmp(h_fig.SelectionType, 'normal')
            kk = get(gca, 'UserData');
            t = get_mouse_pointer_time * config.fs;
            % linearly interpolate
            yval = ([1, 0] + [-1, 1] * (t - floor(t))) * signals{kk}(floor(t) + [0; 1], :);
            text_segment.String = num2str(yval, ' %.3g');
            text_segment.Visible = 'on';
            % the function called next will set text_segment.Position
        end
        % pass through to next function
        axes_button_down_callback(gca, []);
    end

    % left mouse: toggle axes selection
    % left mouse + drag: highlight segment
    % right mouse:
    % - zoom to highlighted segment; remove highlight
    % - zoom out, if no highlight
    % double click left: zoom out full
    % Shift + left or Shift + right: play window or highlighted segment
    % mouse click outside axes: unselect all axes; remove highlight
    last_clicked_axes = [];
    last_button_down = '';
    highlight_start = [];
    function axes_button_down_callback(src, ~)
        n_axes = src.UserData;
        if verbose
            disp(['mouse click on axes ', num2str(n_axes), ', type: ' h_fig.SelectionType, ...
                ', previous: ', last_button_down, ', modifier: ' cell2mat(h_fig.CurrentModifier)]);
        end
        % deal with different types of mouse clicks
        switch(h_fig.SelectionType)
            case 'normal'
                % left mouse: start highlight, move indicator to current axes, setup mouse callbacks
                highlight_start = get_mouse_pointer_time;
                text_segment.Position = [src.Position(1)+ 3, sum(src.Position([2, 4])) - 17, 100, 14];
                h_fig.WindowButtonUpFcn = @button_up_callback;
                h_fig.WindowButtonMotionFcn = @button_motion_callback;
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
                play_src = n_axes;
                start_play;
            case 'open'
                % double click
                switch(last_button_down)
                    case 'normal'
                        % double click left: zoom out full
                        update_selections(last_clicked_axes, 'toggle');
                        set_time_range([0, inf], 1);
                    case 'alt'
                        % right mouse: zoom out 2x
                        zoom_axes(2);
                    case 'extend'
                        % Shift + double click
                        play_src = n_axes;
                        start_play;
                end
        end
        if ~strcmp(h_fig.SelectionType, 'open')
            last_button_down = h_fig.SelectionType;
        end
        last_clicked_axes = n_axes;
    end

    last_action_was_highlight = 0;
    function button_up_callback(~, ~)
        h_fig.WindowButtonUpFcn = '';
        h_fig.WindowButtonMotionFcn = '';
        text_segment.Visible = 'off';
        if last_action_was_highlight
            highlight_range = [highlight_start, get_mouse_pointer_time];
            update_selections(last_clicked_axes, 'add');
        else
            update_selections(last_clicked_axes, 'toggle');
        end
        last_action_was_highlight = 0;
    end

    function button_motion_callback(~, ~)
        highlight_range = [highlight_start, get_mouse_pointer_time];
        delta = abs(diff(highlight_range));
        if delta < 1
            str = [num2str(delta * 1e3, '%.3g'), ' ms (', num2str(round(delta * config.fs)), ')'];
        else
            str = [num2str(delta, '%.3f'), ' sec'];
        end
        text_segment.String = str;
        text_segment.Visible = 'on';
        draw_highlights;
        last_action_was_highlight = 1;
    end

    function window_scroll_callback(~, evt)
        zoom_axes(zoom_per_scroll_wheel_step ^ evt.VerticalScrollCount);
    end

    function slider_moved_callback(~, ~)
        time_diff = diff(time_range_view);
        time_center = 0.5 * time_diff + time_slider.Value * (max(signal_lengths) / config.fs - time_diff);
        set_time_range(time_center + time_diff * [-0.5, 0.5], 0);
    end

    function window_button_down_callback(~, ~)
        % mouse click outside axes
        update_selections([], 'reset');
        delete_highlights;
        highlight_range = [];
    end

    function change_fs_callback(src, ~)
        fs_old = config.fs;
        config.fs = str2double(src.Label);
        set(findall(h_fs.Children, 'Checked', 'on'), 'Checked', 'off');
        src.Checked = 'on';
        write_config();
        highlight_range = highlight_range * fs_old / config.fs;
        set_time_range(time_range_view * fs_old / config.fs, 1);
        spectrum_update;
    end

    function window_resize_callback(~, ~)
        update_layout();
    end

    function window_close_callback(src, ~)
        if src.Number == fig_no
            if ishandle(h_spectrum)
                close(h_spectrum);
            end
        end
        write_config();
        closereq;
    end

    function e = fig_exist(num)
        r = groot;
        e = ~isempty(r.Children) && sum([r.Children(:).Number] == num);
    end

    function write_config
        if verbose
            disp('save config');
        end
        config.Position = h_fig.Position;
        if ishandle(h_spectrum)
            config.spectrum_Position = h_spectrum.Position;
        end
        save(config_file, 'config');
    end
end

% took this from spclab:
function out = reduce(x)
N = 1e4;
[L, chans] = size(x);
if length(x) > 4*N
    d = ceil(L/N);
    N = ceil(L/d);
    out = zeros(2*N, chans);
    for c = 1:chans
        x2=reshape([x(:, c); x(end, c) * ones(N*d-length(x), 1)], d, N);
        out(:, c)=reshape([max(x2); min(x2)], 2*N, 1);
    end
else
    out=x;
end
end
