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
% - show horizontal zoom bar
% - show segment time duration in top left corner
% - FS
% - time on x axis
% - play
% - stop
% - show patch in all selected axes --> only change selection on button

% settings
fig_no = 9372;
config_file = [which('vocle'), 'at'];
axes_label_font_size = 8;
% axes
left_margin = 42;
right_margin = 20;
bottom_margin = 60;
top_margin = 16;
vert_spacing = 28;
figure_color = [0.88, 0.92, 0.96];
selection_color = [0.95, 0.97, 0.98];
segment_color = [0.82, 0.86, 0.92];
zoom_per_scroll_wheel_step = 1.4;

% function-wide variables
time_range_full = [0, 0];
time_range_view = [0, 0];
last_button_down = [];
cursor_line = [];
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
    h.Name = ' vocle';
    h.Color = figure_color;
    if config_exist
        load_config();
    end
end
h_width = h.Position(3);
h_height = h.Position(4);
write_config();

% process signals
num_signals = length(varargin);
signals = cell(num_signals, 1);
signal_lenghts = zeros(num_signals, 1);
signals_negative = zeros(num_signals, 1);
for k = 1:num_signals
    sz = size(varargin{k});
    if sz(1) > sz(2)
        signals{k} = varargin{k};
    else
        signals{k} = varargin{k}';
    end
    signal_lenghts(k) = max(sz);
    signals_negative(k) = min(signals{k}(:)) < 0;
end
time_range_full = [0, max(signal_lenghts)];

% create axes and UI elements, one per input array/matrix
clf;
h_ax = cell(num_signals, 1);
%h_cb = cell(num_signals, 1);
for k = 1:num_signals
    h_ax{k} = axes;
    plot(signals{k}, 'HitTest', 'off');
    h_ax{k}.UserData = k;
    h_ax{k}.FontSize = axes_label_font_size;
    h_ax{k}.Units = 'pixels';
    h_ax{k}.ButtonDownFcn = @axes_button_down_callback;
end
selected_axes = zeros(num_signals, 1);
play_button = uicontrol('Style', 'pushbutton', 'String', 'Play', 'Enable', 'off', 'Callback', @play);
set_time_range(time_range_full);
update_layout;
update_selections([], 'reset');

% set figure callbacks
h.CloseRequestFcn = @window_close_callback;
h.SizeChangedFcn = @window_resize_callback;
h.ButtonDownFcn = @window_button_down_callback;
h.WindowScrollWheelFcn = @window_scroll_callback;
h.WindowButtonUpFcn = '';


    function update_layout
        h_width = h.Position(3);
        h_height = h.Position(4);
        hght = (h_height - top_margin - bottom_margin - (num_signals-1) * vert_spacing) / num_signals;
        width = h_width - left_margin - right_margin;
        if hght > 0 && width > 0
            for k = 1:num_signals
                bottom = bottom_margin + (num_signals - k) * (hght + vert_spacing);
                h_ax{k}.Position = [left_margin, bottom, width, hght];
            end
        end
        play_button.Position = [h_width/2-25, 10, 50, 22];
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
        for k = 1:num_signals
            if selected_axes(k)
                h_ax{k}.Color = [1, 1, 1];
            else
                h_ax{k}.Color = selection_color;
            end
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
        set_time_range([t0, t0 + diff(time_range_view) * factor]);
    end

    % update axis
    function set_time_range(range)
        time_range_view(1) = max(range(1), time_range_full(1));
        time_range_view(2) = min(range(2), time_range_full(2));
        time_range_view(2) = max(time_range_view(1)+1e-4, time_range_view(2));
        % adjust axis, update y scaling
        for k = 1:num_signals
            s = signals{k};
            if time_range_view(1) <= signal_lenghts(k) && time_range_view(2) >= 1
                t0 = max(round(time_range_view(1)), 1);
                t1 = min(round(time_range_view(2)), signal_lenghts(k));
                maxy = 1.1 * max(max(abs(s(t0:t1, :))));
                maxy = max(maxy, 1e-9);
            else
                maxy = 1;
            end
            miny = -maxy * signals_negative(k);
            h_ax{k}.XLim = time_range_view;
            h_ax{k}.YLim = [miny, maxy];
        end
    end

    function axes_button_down_callback(src, evt)
        
        disp(['button down on axes ', num2str(src.UserData), '; type: ' h.SelectionType]);
        
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
        if ~isempty(cursor_line)
            delete(cursor_line);
            cursor_line = [];
        end
        % deal with different types of mouse clicks
        switch(h.SelectionType)
            case 'normal'
                % left mouse: select current axes; setup segment
                update_selections(src.UserData, 'unique');
                ylim = src.YLim;
                ylim(2) = ylim(2) * 0.995;
                cursor_line = line([1, 1] * curr_time, ylim, 'Color', 'k', 'LineStyle', '--', 'HitTest', 'off');
                segment_patch = patch(ones(1, 4) * curr_time, ylim([1, 1, 2, 2]), segment_color, 'LineStyle', 'none', 'HitTest', 'off');
                uistack(segment_patch, 'bottom');
                h.WindowButtonUpFcn = @button_up_callback;
                h.WindowButtonMotionFcn = @button_motion_callback;
            case 'alt'
                if strcmp(h.CurrentModifier, 'control')
                    % Ctrl + left mouse: toggle selection of current axes
                update_selections(src.UserData, 'toggle');
                else
                    % right mouse
                    selected_axes(:) = 0;
                    selected_axes(src.UserData) = 1;
                    update_selections(src.UserData, 'unique');
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
                        update_selections(src.UserData, 'toggle');
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
        if ~isempty(cursor_line)
            delete(cursor_line);
            cursor_line = [];
        end
    end

    function window_scroll_callback(src, evt)
        zoom_axes(zoom_per_scroll_wheel_step ^ evt.VerticalScrollCount);
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

    function window_resize_callback(src, evt)
        update_layout();
    end

    function window_close_callback(src, evt)
        write_config();
        closereq;
    end

    function load_config()
        disp('load config');
        load(config_file, 'config');
        try
            h.Position = config.Position;
        catch
            % invalid config file
            warning('deleting invalid config file');
            delete(config_file);
        end
    end

    function write_config()
        disp('save config');
        config.Position = h.Position;
        save(config_file, 'config');
    end
end
