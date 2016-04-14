function vocle(varargin)
% audio navigator
% ideas:
% - same basic interaction as spclab
% - save configuration such as window location and size, and zoom between calls to vocle
% - checkboxes next to samples
% - drop down menu for sampling rate (and remember)
% - A/B test
% - stereo support
% - start/stop playback
% - different sampling rates per sample?

% settings
fig_no = 9372;
config_file = [which('vocle'), 'at'];
axes_label_font_size = 8;
% axes
left_margin = 42;
%right_margin = 32;
right_margin = 20;
bottom_margin = 80;
top_margin = 16;
vert_spacing = 28;
%checkbox_size = 20;
selection_color = 0.88 * [1, 1, 1];


% function-wide variables
time_range_full = [0, 0];
time_range_view = [0, 0];
last_button_down = [];
selection_patch = [];


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
signals_nonnegative = zeros(num_signals, 1);
for k = 1:num_signals
    sz = size(varargin{k});
    if sz(1) > sz(2)
        signals{k} = varargin{k};
    else
        signals{k} = varargin{k}';
    end
    signal_lenghts(k) = max(sz);
    signals_nonnegative(k) = min(signals{k}(:)) >= 0;
end
time_range_full = [0, max(signal_lenghts)];

% create axes and checkboxes, one per input array/matrix
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
    %h_cb{k} = uicontrol('Style', 'checkbox');
    %h_cb{k}.UserData = k;
    %h_cb{k}.Callback = @axes_checkbox_callback;
end
axes_layout;
time_range_view = time_range_full;
plot_zoom;

% set figure callbacks
h.CloseRequestFcn = @window_close_callback;
h.SizeChangedFcn = @window_resize_callback;
h.ButtonDownFcn = @window_button_down_callback;
h.WindowButtonUpFcn = '';


    % distribute axes over figure
    function axes_layout
        h_width = h.Position(3);
        h_height = h.Position(4);
        hght = (h_height - top_margin - bottom_margin - (num_signals-1) * vert_spacing) / num_signals;
        width = h_width - left_margin - right_margin;
        if hght > 0 && width > 0
            for kh = 1:num_signals
                bottom = bottom_margin + (num_signals-kh) * (hght + vert_spacing);
                h_ax{kh}.Position = [left_margin, bottom, width, hght];
                %h_cb{kh}.Position = [left_margin + width + 8, bottom + hght/2 - checkbox_size*0.77, checkbox_size, 30];
            end
        end
    end

    function t = get_mouse_pointer_time
        frac = (h.CurrentPoint(1) - left_margin) / (h_width - left_margin - right_margin);
        t = time_range_view(1) + frac * diff(time_range_view);
    end

    function plot_zoom
        time_range_view(1) = max(time_range_view(1), time_range_full(1));
        time_range_view(2) = min(time_range_view(2), time_range_full(2));
        % adjust axis, update y scaling
        for k = 1:num_signals
            s = signals{k};
            if time_range_view(1) <= signal_lenghts(k)
                t0 = max(round(time_range_view(1)), 1);
                t1 = min(round(time_range_view(2)), signal_lenghts(k));
                maxy = 1.1 * max(max(abs(s(t0:t1, :))));
            else
                maxy = 1;
            end
            if signals_nonnegative(k)
                miny = 0;
            else
                miny = -maxy;
            end
            h_ax{k}.XLim = time_range_view;
            h_ax{k}.YLim = [miny, maxy];
        end
    end
        
    function zoom_out
        % zoom out 2x
        time_range_view = 0.5 * sum(time_range_view) + diff(time_range_view) * [-1 1];
        time_range_view(1) = max(time_range_full(1), time_range_view(1));
        time_range_view(2) = min(time_range_full(2), time_range_view(2));
        plot_zoom;
    end

    function axes_button_down_callback(src, evt)
        disp(['button down on axes ', num2str(src.UserData)])
        h.SelectionType
        if ~isempty(selection_patch)
            patch_range = selection_patch.Vertices(1:2,1);
            delete(selection_patch);
            selection_patch = [];
        else
            patch_range = [];
        end
        switch(h.SelectionType)
            case 'normal'
                % select current axes
                
                
                selection_patch = patch(ones(1, 4) * get_mouse_pointer_time, kron(src.YLim, [1, 1]), ...
                    selection_color, 'LineStyle', 'none', 'HitTest', 'off');
                uistack(selection_patch, 'bottom');
                h.WindowButtonUpFcn = @button_up_callback;
                h.WindowButtonMotionFcn = @button_motion_callback;
            case 'alt'
                if strcmp(h.CurrentModifier, 'control')
                    % Ctrl + right mouse: toggle selection of current axes
                    
                else
                    % left mouse
                    if isempty(patch_range)
                        % zoom out partially
                        zoom_out;
                    else
                        % zoom to selection
                        time_range_view = sort(patch_range);
                        plot_zoom;
                    end
                end
            case 'open'
                if strcmp(last_button_down, 'normal')
                    % zoom out full
                    time_range_view = time_range_full;
                    plot_zoom;
                else
                    % zoom out partially
                    zoom_out;
                end
        end
        last_button_down = h.SelectionType;
    end
    function button_up_callback(src, evt)
        h.WindowButtonUpFcn = '';
        h.WindowButtonMotionFcn = '';
    end
    function button_motion_callback(src, etc)
        selection_patch.Vertices(2:3,1) = get_mouse_pointer_time;
    end

%     function axes_checkbox_callback(src, evt)
%         disp(['checkbox ', num2str(src.UserData)])
%     end

    function window_button_down_callback(src, evt)
        % unselect all axes
    end

    function window_resize_callback(src, evt)
        disp('resize');
        axes_layout();
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
