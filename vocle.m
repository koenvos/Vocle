function vocle(varargin)
% audio navigator
% ideas:
% - same basic interaction as spclab
% - save configuration such as window location and size, and zoom between calls to vocle
% - checkboxes next to samples
% - A/B test
% - stereo support
% - different sampling rates
% - start/stop playback

% settings
fig_no = 9372;
config_file = [which('vocle'), 'at'];
axes_label_font_size = 8;


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
write_config();

% create axes and checkboxes, one per input array/matrix
clf;
num_axes = length(varargin);
h_ax = cell(num_axes, 1);
h_cb = cell(num_axes, 1);
for k = 1:num_axes
    h_ax{k} = axes;
    plot(varargin{k});
    h_ax{k}.UserData = k;
    h_ax{k}.FontSize = axes_label_font_size;
    h_ax{k}.Units = 'pixels';
    h_ax{k}.ButtonDownFcn = {@axes_button_down_callback};
    h_cb{k} = uicontrol('Style', 'checkbox');
    h_cb{k}.UserData = k;
    h_cb{k}.Callback = {@axes_checkbox_callback};
end
axes_layout;

% set figure callbacks
h.CloseRequestFcn = {@window_close_callback};
h.SizeChangedFcn = {@window_resize_callback};

    % distribute axes over figure
    function axes_layout()
        h_width = h.Position(3);
        h_height = h.Position(4);
        left_margin = 40;
        right_margin = 32;
        bottom_margin = 80;
        top_margin = 8;
        vert_spacing = 25;
        cb_size = 20;
        hght = (h_height - top_margin - bottom_margin - (num_axes-1) * vert_spacing) / num_axes;
        width = h_width - left_margin - right_margin;
        if hght > 0 && width > 0
            for kh = 1:num_axes
                bottom = bottom_margin + (num_axes-kh) * (hght + vert_spacing);
                h_ax{kh}.Position = [left_margin, bottom, width, hght];
                h_cb{kh}.Position = [left_margin + width + 8, bottom + hght/2 - cb_size*0.77, cb_size, 30];
            end
        end
    end

    function axes_button_down_callback(src, evt)
        disp(['button down on axes ', num2str(src.UserData)])
    end

    function axes_checkbox_callback(src, evt)
        disp(['checkbox ', num2str(src.UserData)])
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
