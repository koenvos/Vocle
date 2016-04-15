function vocle(varargin)
% audio navigator
% ideas:
% - same basic interaction as spclab

% advantages over spclab:
% - save configuration such as window location, samping rate, and zoom between calls to vocle
% - A/B test
% - scroll wheel zooming
% - stereo support
% - start/stop playback
% - different sampling rates per sample?

% todo:
% - show segment time duration in top left corner
% - play
% - stop
% - animated cursor
% - y scaling of segment patch and cursor line when zooming
% - show patch in all selected axes --> only change selection on button

% settings
fig_no = 9372;
config_file = [which('vocle'), 'at'];
axes_label_font_size = 8;
% axes
left_margin = 42;
right_margin = 20;
bottom_margin = 90;
top_margin = 16;
vert_spacing = 27;
slider_height = 16;
if 0
    % blue colors
    figure_color = [0.9, 0.93, 0.96];
    selection_color = [0.95, 0.97, 0.985];
else
    % gray colors
    figure_color = [0.935, 0.939, 0.94];
    selection_color = [0.973, 0.976, 0.978];
end
segment_color = [0.88, 0.92, 0.96];
zoom_per_scroll_wheel_step = 1.3;
ylim_margin = 1.1;
fs = 48000;

% function-wide variables
h_ax = [];
selected_axes = [];
time_range_full = [0, 0];
time_range_view = [0, 0];
last_button_down = [];
%cursor_line = [];
segment_patch = [];


% detect if figure exists
r = groot;
fig_exist = ~isempty(r.Children) && sum([r.Children(:).Number] == fig_no);

% detect if config file exists
config_exist = exist(config_file, 'file');

% create figure if needed and sync with config file
h = figure(fig_no);
if ~fig_exist
    h.NumberTitle = 'off';
    h.ToolBar = 'none';
    h.MenuBar = 'none';
    h.Name = ' Vocle';
    h.Color = figure_color;
    if config_exist
        load_config;
    end
end
h_width = h.Position(3);
h_height = h.Position(4);
write_config();

% process signals
num_signals = length(varargin);
signals = cell(num_signals, 1);
signal_times = zeros(num_signals, 1);
signals_negative = zeros(num_signals, 1);
signals_ylim = zeros(num_signals, 1);
for k = 1:num_signals
    sz = size(varargin{k});
    if sz(1) > sz(2)
        signals{k} = varargin{k};
    else
        signals{k} = varargin{k}';
    end
    s_ = signals{k}(:);
    signals_negative(k) = min(s_) < 0;
    signals_ylim(k) = ylim_margin * max(abs(s_));
end

clf;
% create axes, one per input signal
selected_axes = zeros(num_signals, 1);
h_ax = cell(num_signals, 1);
for k = 1:num_signals
    h_ax{k} = axes;
    h_ax{k}.Units = 'pixels';
end
time_slider = uicontrol(h, 'Style', 'slider', 'Value', 0.5, 'BackgroundColor', selection_color, 'Callback', @slider_moved);
popup = uicontrol(h, 'Style', 'popup', 'String', {'192000', '96000', '48000', '44100', '32000', '16000', '8000'}, 'Callback', @change_fs_callback);
text_fs = uicontrol(h, 'Style', 'text', 'String', 'Sampling Rate', 'FontName', 'Helvetica', 'BackgroundColor', figure_color, 'HitTest', 'Off');    
play_button = uicontrol(h, 'Style', 'pushbutton', 'String', 'Play', 'Enable', 'off', 'Callback', @play);
update_layout;

plot_signals;
       
% set figure callbacks
h.CloseRequestFcn = @window_close_callback;
h.SizeChangedFcn = @window_resize_callback;
h.ButtonDownFcn = @window_button_down_callback;
h.WindowScrollWheelFcn = @window_scroll_callback;
h.WindowButtonUpFcn = '';

    % plot signals at the right sampling rate
    function plot_signals
        % make sure the correct sampling rate is shown in drop-down menu
        popup.Value = find(str2double(popup.String) == fs);
        for kk = 1:num_signals
            t = (1:length(signals{kk})) / fs;
            signal_times(kk) = t(end);
            plot(h_ax{kk}, t, signals{kk}, 'HitTest', 'off');
            h_ax{kk}.UserData = kk;
            h_ax{kk}.Color = selection_color.^(1-selected_axes(kk));
            h_ax{kk}.ButtonDownFcn = @axes_button_down_callback;
            h_ax{kk}.Layer = 'top';
            h_ax{kk}.FontSize = axes_label_font_size;
        end
        segment_patch = [];
        time_range_full = [0, max(signal_times)];
        set_time_range(time_range_full);
    end

    function update_layout
        h_width = h.Position(3);
        h_height = h.Position(4);
        hght = (h_height - top_margin - bottom_margin - (num_signals-1) * vert_spacing) / num_signals;
        width = h_width - left_margin - right_margin;
        if hght > 0 && width > 0
            for kk = 1:num_signals
                bottom = bottom_margin + (num_signals - kk) * (hght + vert_spacing);
                h_ax{kk}.Position = [left_margin, bottom, width, hght];
            end
        end
        play_button.Position = [h_width/2-25, 12, 50, 22];
        time_slider.Position = [left_margin - 11, bottom_margin - vert_spacing - slider_height, width + 22, slider_height];
        popup.Position = [h_width-70, 12, 58, 22];
        text_fs.Position = [h_width-147, 9, 74, 22];
    end

    function update_selections(ind, type)
        if num_signals == 1
            selected_axes = 1;
        end
        switch(type)
            case {'unique', 'reset'}
                selected_axes(:) = 0;
                selected_axes(ind) = 1;
            case 'toggle'
                selected_axes(ind) = 1 - selected_axes(ind);
        end
        if sum(selected_axes) == 1
            play_button.Enable = 'on';
        else
            play_button.Enable = 'off';
        end
        for kk = 1:num_signals
            h_ax{kk}.Color = selection_color.^(1-selected_axes(kk));
        end
    end

    function t = get_mouse_pointer_time
        frac = (h.CurrentPoint(1) - left_margin) / (h_width - left_margin - right_margin);
        t = time_range_view(1) + frac * diff(time_range_view);
    end

    function zoom_axes(factor)
        % factor > 1: zoom out; factor < 1: zoom in
        % keep time under mouse constant
        tmouse = get_mouse_pointer_time;
        tmouse = min(max(tmouse, time_range_view(1)), time_range_view(2));
        t0 = tmouse - (tmouse - time_range_view(1)) * factor;
        interval = diff(time_range_view) * factor;
        t0 = max(t0, time_range_full(1));
        t1 = t0 + interval;
        t1 = min(t1, time_range_full(2));
        set_time_range([t1 - interval, t1]);
    end

    % update axis
    function set_time_range(range)
        time_range_view(1) = max(range(1), time_range_full(1));
        time_range_view(2) = min(range(2), time_range_full(2));
        time_range_view(2) = max(time_range_view(1)+1e-4, time_range_view(2));
        % adjust axis, update y scaling
        for kk = 1:num_signals
            s = signals{kk};
            if time_range_view(1) <= signal_times(kk) && time_range_view(2)*fs >= 1
                t0 = max(round(time_range_view(1)*fs), 1);
                t1 = min(round(time_range_view(2)*fs), length(s));
                maxy = 1.1 * max(max(abs(s(t0:t1, :))));
                maxy = max(maxy, 1e-9);
            else
                maxy = 1;
            end
            miny = -maxy * signals_negative(kk);
            h_ax{kk}.XLim = time_range_view;
            h_ax{kk}.YLim = [miny, maxy];
        end
        time_diff = diff(time_range_view);
        frac_time = time_diff / diff(time_range_full);
        val = (mean(time_range_view) - time_diff / 2 + 1e-6) / (diff(time_range_full) - time_diff + 2e-6);
        time_slider.Value = min(max(val, 0), 1);
        if 1
            % zooming out fully, the slider should take up the entire width; but it doesn't
            time_slider.SliderStep = [0.25, 1] * frac_time;
        else
            % this fixes the width problem of the slider, but doesn't work
            % reliably: sometimes the slider is in the wrong position
            time_slider.SliderStep = [0.1, 1 / (1.0001 - frac_time)] * frac_time;
        end
    end

    function axes_button_down_callback(src, evt)
        n_axes = src.UserData;
        disp(['button down on axes ', num2str(n_axes), '; type: ' h.SelectionType]);
        
        curr_time = get_mouse_pointer_time;
        % remove segment patch (but remember its range)
        if ~isempty(segment_patch)
            segment_range = sort(segment_patch.Vertices(1:2, 1));
            delete(segment_patch);
            segment_patch = [];
        else
            segment_range = [];
        end
        % remove cursor line
        %         if ~isempty(cursor_line)
        %             delete(cursor_line);
        %             cursor_line = [];
        %         end
        % deal with different types of mouse clicks
        switch(h.SelectionType)
            case 'normal'
                % left mouse: select current axes; setup segment
                update_selections(n_axes, 'unique');
                %                cursor_line = line([1, 1] * curr_time, ylim, 'Color', 'k', 'LineStyle', '--', 'HitTest', 'off');
                segment_patch = patch(ones(1, 4) * curr_time, signals_ylim(n_axes) * [-1, -1, 1, 1], ...
                    segment_color, 'LineStyle', 'none', 'HitTest', 'off');
                uistack(segment_patch, 'bottom');
                h.WindowButtonUpFcn = @button_up_callback;
                h.WindowButtonMotionFcn = @button_motion_callback;
            case 'alt'
                if strcmp(h.CurrentModifier, 'control')
                    % Ctrl + left mouse: toggle selection of current axes
                    update_selections(n_axes, 'toggle');
                else
                    % right mouse
                    selected_axes(:) = 0;
                    selected_axes(n_axes) = 1;
                    update_selections(n_axes, 'unique');
                    if isempty(segment_range) || diff(segment_range) == 0
                        % zoom out 2x around current time
                        zoom_axes(2);
                    else
                        % zoom to selection
                        set_time_range(segment_range);
                    end
                end
            case 'open'
                % double click
                if strcmp(last_button_down, 'normal')
                    % double click left: zoom out full
                    set_time_range(time_range_full);
                else
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
    function button_up_callback(src, evt)
        h.WindowButtonUpFcn = '';
        h.WindowButtonMotionFcn = '';
    end
    function button_motion_callback(src, evt)
        % mouse is dragged across an axes
        segment_patch.Vertices(2:3,1) = get_mouse_pointer_time;
        %         if ~isempty(cursor_line)
        %             delete(cursor_line);
        %             cursor_line = [];
        %         end
    end

    function window_scroll_callback(src, evt)
        zoom_axes(zoom_per_scroll_wheel_step ^ evt.VerticalScrollCount);
    end

    function slider_moved(src, evt)
        time_diff = diff(time_range_view);
        time_center = 0.5 * time_diff + time_slider.Value * (diff(time_range_full) - time_diff);
        set_time_range(time_center + time_diff * [-0.5, 0.5]);
    end

    function play(varargin)
        if strcmp(play_button.String, 'Play')
            play_button.String = 'Stop';
        else
            play_button.String = 'Play';
        end
        disp('playing');
    end

    function window_button_down_callback(src, evt)
        % unselect all axes
        update_selections([], 'reset');
    end

    function change_fs_callback(src, evt)
        fs = str2double(src.String{src.Value});
        plot_signals;
    end

    function window_resize_callback(src, evt)
        update_layout();
    end

    function window_close_callback(src, evt)
        write_config();
        closereq;
    end

    function load_config
        disp('load config');
        load(config_file, 'config');
        try
            h.Position = config.Position;
            fs = config.fs;
        catch
            % invalid config file
            warning('deleting invalid config file');
            delete(config_file);
        end
    end

    function write_config()
        disp('save config');
        config.Position = h.Position;
        config.fs = fs;
        save(config_file, 'config');
    end
end
