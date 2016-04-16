function vocle(varargin)
% audio navigator
% 
% same basic interaction as spclab
% advantages over spclab:
% - save configuration such as window location, samping rate between calls to vocle
% - scroll wheel zooming
% - stereo support
% - stop playback
% - A/B test
% - different sampling rates per sample?
% - auto align function?

% todo:
% - play segment
% - A/B test
% - spectrum
% - spectrogram

% settings
fig_no = 9372;
config_file = [which('vocle'), 'at'];
axes_label_font_size = 8;
% space around and between axes
left_margin = 42;
right_margin = 18;
bottom_margin = 100;
top_margin = 14;
vert_spacing = 27;
slider_height = 16;
button_height = 20;
figure_color = [0.895, 0.898, 0.9];
selection_color = [0.945, 0.948, 0.95];
segment_color = [0.7, 0.8, 0.9];
zoom_per_scroll_wheel_step = 1.4;
ylim_margin = 1.1;
playback_fs = 48000;
playback_bits = 24;
playback_dBov = -3;

% check if first argument is sampling rate
if isscalar(varargin{1})
    fs = varargin{1};
    fs_given = 1;
else
    fs = 48000;  % default; overwritten if config file exists
    fs_given = 0;
end

% detect if figure exists
r = groot;
fig_exist = ~isempty(r.Children) && sum([r.Children(:).Number] == fig_no);

% create figure if doesn't exist yet 
h = figure(fig_no);
h.NumberTitle = 'off';
h.ToolBar = 'none';
h.MenuBar = 'none';
h.Name = ' Vocle';
h.Color = figure_color;

% load configuration, if possible
load_config(fig_exist, fs_given);

% process signals
num_signals = length(varargin);
signals = cell(num_signals, 1);
signal_lengths = zeros(num_signals, 1);
signals_negative = zeros(num_signals, 1);
signals_ylim = zeros(num_signals, 1);
for k = 1:num_signals
    sz = size(varargin{k});
    signal_lengths(k) = max(sz);
    if sz(1) > sz(2)
        signals{k} = varargin{k};
    else
        signals{k} = varargin{k}';
    end
    s_ = signals{k}(:);
    signals_negative(k) = min(s_) < 0;
    signals_ylim(k) = ylim_margin * max(abs(s_));
end

% function-wide variables
h_ax = [];
selected_axes = [];
time_range_view = [];
last_button_down = [];
segment_range = [];
segment_patches = cell(num_signals, 1);
play_cursor = [];
player = [];

% put elements on UI
clf;
h_ax = cell(num_signals, 1);
for k = 1:num_signals
    h_ax{k} = axes;
    h_ax{k}.Units = 'pixels';
end
time_slider = uicontrol(h, 'Style', 'slider', 'Value', 0.5, 'BackgroundColor', selection_color);
slider_listener = addlistener(time_slider, 'Value', 'PostSet', @slider_moved_callback);
text_fs = uicontrol(h, 'Style', 'text', 'String', 'Sampling Rate', ...
    'FontName', 'Helvetica', 'BackgroundColor', figure_color);
text_segment = uicontrol(h, 'Style', 'text', 'FontName', 'Helvetica', ...
    'BackgroundColor', [1, 1, 1], 'Visible', 'off', 'HitTest', 'Off');
popup_fs = uicontrol(h, 'Style', 'popup', 'String', ...
    {'192000', '96000', '48000', '44100', '32000', '16000', '8000'}, 'Callback', @change_fs_callback);
popup_fs.Value = find(str2double(popup_fs.String) == fs);
play_button = uicontrol(h, 'Style', 'pushbutton', 'String', 'Play', 'FontSize', 10, 'Callback', @play_callback);
update_layout;

% show signals
update_selections([], 'reset');
set_time_range([0, inf]);

% set figure callbacks
h.CloseRequestFcn = @window_close_callback;
h.SizeChangedFcn = @window_resize_callback;
h.ButtonDownFcn = @window_button_down_callback;
h.WindowScrollWheelFcn = @window_scroll_callback;
h.WindowButtonUpFcn = '';

    % position UI elements
    function update_layout
        h_width = h.Position(3);
        h_height = h.Position(4);
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
        play_button.Position = [h_width/2-25, (slider_bottom-button_height)/2-3, 50, button_height+6];  % extra big
        popup_fs.Position = [h_width-70, (slider_bottom-button_height)/2, 58, button_height];
        text_fs.Position = [h_width-147, (slider_bottom-button_height)/2-4, 74, button_height];
    end

    function update_selections(ind, type)
        if num_signals == 1
            selected_axes = 1;
        else
            switch(type)
                case {'unique', 'reset'}
                    selected_axes = zeros(num_signals, 1);
                    selected_axes(ind) = 1;
                case 'toggle'
                    selected_axes(ind) = 1 - selected_axes(ind);
            end
        end
        if sum(selected_axes) == 1
            play_button.Enable = 'on';
        elseif strcmp(play_button.String, 'Play')  % don't disable during playback
            play_button.Enable = 'off';
        end
        for kk = 1:num_signals
            h_ax{kk}.Color = selection_color.^(1-selected_axes(kk));
        end
    end

    % plot signals
    function plot_signals
        delete_patches;   % they wouldn't survive the plotting
        for kk = 1:num_signals
            t0 = max(floor(time_range_view(1)*fs), 1);
            t1 = min(ceil(time_range_view(2)*fs), signal_lengths(kk));
            s = signals{kk};
            s_ = reduce(s(t0:t1, :));
            t = (t0 + (0:size(s_, 1)-1) * (t1-t0+1) / length(s_)) / fs;
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
        draw_patches;
    end

    function t = get_mouse_pointer_time
        frac = (h.CurrentPoint(1) - left_margin) / (h.Position(3) - left_margin - right_margin);
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
        t1 = min(t1, max(signal_lengths) / fs);
        set_time_range([t1 - interval, t1]);
    end

    % update axis
    function set_time_range(range, update_slider)
        min_delta = 10 / fs;
        max_time = max(signal_lengths) / fs;
        time_range_view(1) = min(max(range(1), 0), max_time - min_delta);
        time_range_view(2) = max(min(range(2), max_time), 0 + min_delta);
        time_range_view = time_range_view + max(min_delta - diff(time_range_view), 0) * [-0.5, 0.5];
        % update signals
        plot_signals;
        % update slider
        if nargin < 2 || update_slider
            time_diff = diff(time_range_view);
            val = (mean(time_range_view) - time_diff / 2 + 1e-6) / (max_time - time_diff + 2e-6);
            slider_listener.Enabled = 0;
            time_slider.Value = min(max(val, 0), 1);
            slider_listener.Enabled = 1;
            frac_time = time_diff / max_time;
            if 1
                % zooming out fully, the slider should take up the entire width; but it doesn't
                time_slider.SliderStep = [0.1, 1] * frac_time;
            else
                % this fixes the width problem of the slider, but doesn't work
                % reliably: sometimes the slider is in the wrong position
                time_slider.SliderStep = [0.1, 1 / (1.0001 - frac_time)] * frac_time;
            end
        end
    end

    function delete_patches
        for kk = 1:num_signals
            if ~isempty(segment_patches{kk})
                delete(segment_patches{kk});
                segment_patches{kk} = [];
            end
        end
    end

    function draw_patches
        if ~isempty(segment_range)
            for kk = 1:num_signals
                if isempty(segment_patches{kk})
                    segment_patches{kk} = patch(segment_range([1, 2, 2, 1]), signals_ylim(kk) * [-1, -1, 1, 1], ...
                        segment_color, 'Parent', h_ax{kk}, 'LineStyle', 'none', 'FaceAlpha', 0.4, 'HitTest', 'off');
                    uistack(segment_patches{kk}, 'bottom');
                else
                    segment_patches{kk}.Vertices(:, 1) = segment_range([1, 2, 2, 1]);
                end
            end
        end
    end

    function plot_button_down_callback(~, ~)
        src = gca;
        if strcmp(h.SelectionType, 'normal')
            n_axes = src.UserData;
            t = get_mouse_pointer_time * fs;
            % linearly interpolate
            yval = signals{n_axes}(floor(t) + [0; 1])' * ([1; 0] + [-1; 1] * (t - floor(t)));
            text_segment.String = num2str(yval, ' %.3g');
            text_segment.Visible = 'on';
            % the function below will set text_segment.Position
        end
        % pass through to next function
        axes_button_down_callback(gca, []);
    end

    % left mouse: select axes and unselect all others; remove highlight
    % left mouse + drag: highlight segment
    % right mouse:
    % - zoom to highlighted segment; remove highlight
    % - zoom out, if no highlight
    % double click left: left mouse + zoom out full
    % Ctrl + left: toggle selection of axes
    % Shift + left: select axes and unselect all others; play window or highlighted segment
    function axes_button_down_callback(src, ~)
        n_axes = src.UserData;
        disp(['button down on axes ', num2str(n_axes), '; type: ' h.SelectionType]);
        curr_time = get_mouse_pointer_time;
        delete_patches;
        zoom_range = segment_range;
        segment_range = [];
        % deal with different types of mouse clicks
        switch(h.SelectionType)
            case 'normal'
                % left mouse: select current axes; setup segment
                update_selections(n_axes, 'unique');
                segment_range = curr_time * [1, 1];
                draw_patches;
                text_segment.Position = [src.Position(1)+ 3, sum(src.Position([2, 4])) - 17, 100, 14];
                % cursor_line = line([1, 1] * curr_time, ylim, 'Color', 'k', 'LineStyle', '--', 'HitTest', 'off');
                h.WindowButtonUpFcn = @button_up_callback;
                h.WindowButtonMotionFcn = @button_motion_callback;
            case 'extend'
                update_selections(n_axes, 'unique');
                play_callback('force_start');
            case 'alt'
                if strcmp(h.CurrentModifier, 'control')
                    % Ctrl + left mouse: toggle selection of current axes
                    update_selections(n_axes, 'toggle');
                else
                    % right mouse
                    selected_axes(:) = 0;
                    selected_axes(n_axes) = 1;
                    update_selections(n_axes, 'unique');
                    if ~exist('zoom_range', 'var') || isempty(zoom_range) || diff(zoom_range) == 0
                        % zoom out 2x
                        zoom_axes(2);
                    else
                        % zoom to segment
                        set_time_range(sort(zoom_range));
                    end
                end
            case 'open'
                % double click
                switch(last_button_down)
                    case 'normal'
                        % double click left: zoom out full
                        set_time_range([0, inf]);
                    case 'extend'
                        update_selections(n_axes, 'unique');
                        play_callback('force_start');
                    case 'alt'
                        % double click 'alt': treat as second of two separate clicks
                        if strcmp(h.CurrentModifier, 'control')
                            % Ctrl + left mouse: toggle selection of current axes
                            update_selections(n_axes, 'toggle');
                        else
                            % zoom out 2x
                            zoom_axes(2);
                        end
                end
        end
        last_button_down = h.SelectionType;
    end

    function button_up_callback(~, ~)
        h.WindowButtonUpFcn = '';
        h.WindowButtonMotionFcn = '';
        text_segment.Visible = 'off';
    end

    function button_motion_callback(~, ~)
        segment_range(2) = get_mouse_pointer_time;
        delta = abs(diff(segment_range));
        if delta < 1
            str = [num2str(delta * 1e3, '%.3g'), ' ms (', num2str(round(delta * fs)), ')'];
        else
            str = num2str(delta, '%.3f');
        end
        text_segment.String = str;
        text_segment.Visible = 'on';
        draw_patches;
    end

    function window_scroll_callback(~, evt)
        zoom_axes(zoom_per_scroll_wheel_step ^ evt.VerticalScrollCount);
    end

    function slider_moved_callback(~, ~)
        time_diff = diff(time_range_view);
        time_center = 0.5 * time_diff + time_slider.Value * (max(signal_lengths) / fs - time_diff);
        set_time_range(time_center + time_diff * [-0.5, 0.5], 0);
    end

    function [s, t0 , t1] = get_current_signal(kk, apply_win)
        s = signals{kk};
        if ~isempty(segment_range) && abs(diff(segment_range)) > 0
            t0 = min(segment_range);
            t1 = max(segment_range);
        else
            t0 = time_range_view(1);
            t1 = time_range_view(2);
        end
        t0 = max(round(t0 * fs), 1);
        t1 = min(round(t1 * fs), signal_lengths(kk));
        s = s(t0:t1, :);
        smpls = size(s, 1);
        if nargin > 1 && apply_win
            % windowing
            fade_smpls = min(fs / 100, smpls / 2);
            win = sin((1:fade_smpls)'/(fade_smpls+1)*pi/2) .^ 2;
            t = 1:fade_smpls;
            s(t, :) = bsxfun(@times, s(t, :), win);
            s(end-t+1, :) = bsxfun(@times, s(end-t+1, :), win);
        end
        t0 = t0 / fs;
        t1 = t1 / fs;
    end

    function play_callback(varargin)
        if strcmp(play_button.String, 'Play') || (ischar(varargin{1}) && strcmp(varargin{1}, 'force_start'))
            % stop any ongoing playback before starting a new one
            try 
                stop(player);
                delete(play_cursor);
            catch
            end
            kk = find(selected_axes, 1);
            [s, t0, t1] = get_current_signal(kk, 1);
            s = s / (signals_ylim(kk) / ylim_margin) * 10^(0.05*playback_dBov);
            s = resample([zeros(round(fs/100), size(s, 2)); s; zeros(round(fs/100), size(s, 2))], playback_fs, fs, 50);
            s = min(max(s, -1), 1);
            player = audioplayer(s, playback_fs, playback_bits);
            play(player);
            play_button.String = 'Stop';
            pause(0.05);
            tval = tic;
            while t0 + toc(tval) < t1 && strcmp(play_button.String, 'Stop')
                if ~isempty(play_cursor) && isvalid(play_cursor)
                    % race condition: plot() could be called here through a callback, deleting the line
                    try
                        play_cursor.XData = [1, 1] * (t0 + toc(tval));
                    catch
                    end
                else
                    play_cursor = line([1, 1] * (t0 + toc(tval)), signals_ylim(kk) * [-1, 1], 'Color', 'k', 'HitTest', 'off');
                end
                pause(0.01);
            end
            try
                delete(play_cursor);
            catch
            end
            play_button.String = 'Play';
        else
            try 
                stop(player);
            catch
            end
            play_button.String = 'Play';
        end
        % make sure to leave the Play button in the right state
        update_selections([], '');
    end

    function window_button_down_callback(~, ~)
        % mouse click outside axes
        update_selections([], 'reset');
        delete_patches;
        segment_range = [];
    end

    function change_fs_callback(src, ~)
        fs_old = fs;
        fs = str2double(src.String{src.Value});
        write_config();
        segment_range = segment_range * fs_old / fs;
        set_time_range(time_range_view * fs_old / fs);
    end

    function window_resize_callback(~, ~)
        write_config();
        update_layout();
    end

    function window_close_callback(~, ~)
        write_config();
        closereq;
    end

    function load_config(keep_position, keep_fs)
        disp('load config');
        if exist(config_file, 'file')
            load(config_file, 'config');
            try
                if ~keep_position
                    h.Position = config.Position;
                end
                if ~keep_fs
                    fs = config.fs;
                end
            catch
                warning('invalid config file');
            end
        end
        write_config;
    end

    function write_config
        disp('save config');
        config.Position = h.Position;
        config.fs = fs;
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
