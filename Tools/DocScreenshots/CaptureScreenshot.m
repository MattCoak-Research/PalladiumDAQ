function changed = CaptureScreenshot(fig, file, options)
%CAPTURESCREENSHOT - Save a screenshot of a uifigure, or of one component in it, with numbered highlights.
%
%   changed = CaptureScreenshot(fig, file) saves the contents of uifigure
%   fig (without the window's title bar) as the PNG image file.
%
%   Name-value options:
%   * Target     - a component in fig to crop the image to, plus Margin
%                  pixels around it. Default [], the whole window
%   * Margin     - pixels around the Target to include. Default 8
%   * Highlights - cell array of components in fig to outline and number
%                  1, 2, 3... in that order. Default {}
%   * TitleBar   - add a window title bar (with the window's icon and Name,
%                  in the Windows 11 style) above the image. Default true
%                  for whole windows, false when cropping to a Target
%   * Tolerance  - fraction of pixels that may differ from an existing
%                  file without it being rewritten, for images that vary a
%                  little from run to run (e.g. plots of simulated data).
%                  Default 0
%
%   exportapp captures a window's contents only, so the title bar is drawn
%   rather than captured - a real one varies with the computer's theme and
%   wallpaper, which would make the images differ between computers.
%
%   Positions come from the components themselves, so crops and highlights
%   follow any change in the GUI's layout. Images are scaled to 100% if the
%   display is scaled. The file is only written if the image has changed,
%   so unchanged screenshots don't show up as changes in git.
%
%   Outputs:
%   changed - true if the file was written

arguments
    fig (1,1) matlab.ui.Figure
    file (1,1) string
    options.Target = []
    options.Margin (1,1) double = 8
    options.Highlights cell = {}
    options.Tolerance (1,1) double = 0
    options.TitleBar = []
end
if isempty(options.TitleBar)
    options.TitleBar = isempty(options.Target);
end

HighlightColour = [0.85 0.33 0.10];    %Orange, as the docs' headings

%Give the window itself keyboard focus, so no text field shows a focus
%border - which field has focus otherwise varies from run to run. Then let
%it finish drawing, and export its contents
focus(fig);
drawnow;
pause(1);
tempFile = string(tempname) + ".png";
exportapp(fig, tempFile);
image = imread(tempFile);
delete(tempFile);

%Region to keep, in figure pixels: [left bottom width height], 1-based
figSize = fig.Position(3:4);
scale = size(image, 2) / figSize(1);
if isempty(options.Target)
    region = [1, 1, figSize];
else
    pos = getpixelposition(options.Target, true);
    left = max(1, pos(1) - options.Margin);
    bottom = max(1, pos(2) - options.Margin);
    right = min(figSize(1), pos(1) + pos(3) - 1 + options.Margin);
    top = min(figSize(2), pos(2) + pos(4) - 1 + options.Margin);
    region = [left, bottom, right - left + 1, top - bottom + 1];
end

%Crop - image rows count down from the top of the window
rows = round((figSize(2) - (region(2) + region(4) - 1)) * scale) + 1 : round((figSize(2) - region(2) + 1) * scale);
cols = round((region(1) - 1) * scale) + 1 : round((region(1) + region(3) - 1) * scale);
image = image(rows(rows >= 1 & rows <= size(image, 1)), cols(cols >= 1 & cols <= size(image, 2)), :);

%Normalise to 100% scale, so screenshots are consistent between displays
if abs(scale - 1) > 0.01
    image = imresize(image, round(region([4 3])));
end

if ~isempty(options.Highlights)
    image = DrawHighlights(image, region, options.Highlights, HighlightColour);
end

if options.TitleBar
    image = AddTitleBar(image, fig);
end

%Only write the file if the image has changed (beyond the Tolerance)
changed = true;
if isfile(file)
    old = imread(file);
    if isequal(size(old), size(image))
        differentPixels = mean(any(old ~= image, 3), "all");
        changed = differentPixels > options.Tolerance;
    end
end
if changed
    imwrite(image, file);
end
end

function image = DrawHighlights(image, region, components, colour)
%Outline each component, with a numbered marker at its top-left corner.
%Drawn straight onto the image's pixels, so the screenshot itself is never
%resampled and stays sharp
[h, w, ~] = size(image);
image = double(image) / 255;
lineWidth = 3;
badgeRadius = 13;

for k = 1 : numel(components)
    %Component position in image pixels (from the top-left of the crop)
    pos = round(getpixelposition(components{k}, true));
    x1 = pos(1) - region(1) + 1;
    y1 = (region(2) + region(4)) - (pos(2) + pos(4)) + 1;
    x2 = x1 + pos(3) - 1;
    y2 = y1 + pos(4) - 1;

    %Outline, drawn just inside the component's edge
    mask = false(h, w);
    rows = max(1, y1) : min(h, y2);
    cols = max(1, x1) : min(w, x2);
    mask(rows, cols) = true;
    inner = false(h, w);
    inner(max(1, y1 + lineWidth) : min(h, y2 - lineWidth), max(1, x1 + lineWidth) : min(w, x2 - lineWidth)) = true;
    image = Blend(image, double(mask & ~inner), colour);

    %Numbered marker, centred on the top-left corner but kept inside the image
    cx = min(max(x1, badgeRadius + 2), w - badgeRadius - 2);
    cy = min(max(y1, badgeRadius + 2), h - badgeRadius - 2);
    [X, Y] = meshgrid(1:w, 1:h);
    distance = sqrt((X - cx).^2 + (Y - cy).^2);
    image = Blend(image, min(max(badgeRadius + 1.5 - distance, 0), 1), [1 1 1]);   %White rim
    image = Blend(image, min(max(badgeRadius - distance, 0), 1), colour);
    glyph = NumberGlyph(k, 2 * badgeRadius - 10);
    [gh, gw] = size(glyph);
    top = round(cy - gh/2);
    left = round(cx - gw/2);
    alpha = zeros(h, w);
    alpha(top : top + gh - 1, left : left + gw - 1) = glyph;
    image = Blend(image, alpha, [1 1 1]);
end
image = uint8(round(image * 255));
end

function image = AddTitleBar(image, fig)
%Draw a window title bar above the image, in the Windows 11 style: the
%window's icon and title on the left, minimise, maximise and close buttons
%on the right, and a thin border around the whole window
barHeight = 30;
background = [239 244 249] / 255;
foreground = [0.1 0.1 0.1];
buttonWidth = 46;

w = size(image, 2);
bar = repmat(reshape(background, 1, 1, 3), barHeight, w);

%Icon, 16 x 16 pixels - the window's own, or MATLAB's default as a real
%window shows
iconLeft = 9;
iconFile = string(fig.Icon);
if isempty(fig.Icon) || ~isfile(iconFile)
    iconFile = fullfile(matlabroot, "toolbox", "matlab", "icons", "matlabicon.gif");
end
if isfile(iconFile)
    [icon, iconAlpha] = ReadIcon(iconFile);
    icon = ResizeNearest(icon, [16 16]);
    iconAlpha = ResizeNearest(iconAlpha, [16 16]);
    rows = 8 : 23;
    cols = iconLeft : iconLeft + 15;
    region = bar(rows, cols, :);
    bar(rows, cols, :) = region .* (1 - iconAlpha) + icon .* iconAlpha;
end

%Title
mask = TextMask(string(fig.Name), 12);
[th, tw] = size(mask);
tw = min(tw, w - 3*buttonWidth - 40);
top = round((barHeight - th) / 2) + 1;
alpha = zeros(barHeight, w);
alpha(top : top + th - 1, 33 : 32 + tw) = mask(:, 1:tw);
bar = Blend(bar, alpha, foreground);

%Minimise, maximise and close buttons, each a 10 pixel glyph centred in
%its button
centreY = barHeight / 2 + 1;
glyph = zeros(barHeight, w);
for b = 1 : 3
    cx = w - (3 - b) * buttonWidth - buttonWidth / 2;
    x1 = round(cx - 5);
    y1 = round(centreY - 5);
    switch b
        case 1  %Minimise - a horizontal line
            glyph(round(centreY), x1 : x1 + 10) = 1;
        case 2  %Maximise - a square
            glyph(y1, x1 : x1 + 9) = 1;
            glyph(y1 + 9, x1 : x1 + 9) = 1;
            glyph(y1 : y1 + 9, x1) = 1;
            glyph(y1 : y1 + 9, x1 + 9) = 1;
        case 3  %Close - a cross
            for k = 0 : 9
                glyph(y1 + k, x1 + k) = 1;
                glyph(y1 + k, x1 + 9 - k) = 1;
            end
    end
end
bar = Blend(bar, glyph, foreground);

%Stack, then draw a thin grey border around the whole window
image = [uint8(round(bar * 255)); image];
[h, w, ~] = size(image);
border = false(h, w);
border([1 h], :) = true;
border(:, [1 w]) = true;
image = uint8(round(Blend(double(image) / 255, double(border), [0.75 0.75 0.75]) * 255));
end

function mask = TextMask(textString, fontSize)
%Anti-aliased mask (0 to 1) of a line of text, rendered at its actual size
%in a hidden figure so that it is as crisp as the GUI's own text
fig = figure(Visible="off", Units="pixels", Position=[100 100 1200 60], Color="w", MenuBar="none", ToolBar="none");
closeFig = onCleanup(@() close(fig));
ax = axes(fig, Units="pixels", Position=[1 1 1200 60], XLim=[0 1200], YLim=[0 60], Visible="off");
text(ax, 2, 30, textString, FontName="Segoe UI", FontUnits="pixels", FontSize=fontSize, ...
    Color="k", VerticalAlignment="middle", Interpreter="none");
frame = getframe(fig);
mask = 1 - rgb2gray_(frame.cdata) / 255;
[r, c] = find(mask > 0.03);
mask = mask(max(1, min(r) - 1) : max(r) + 1, max(1, min(c) - 1) : max(c) + 1);
end

function [rgb, alpha] = ReadIcon(file)
%An icon image as RGB (0 to 1) with its transparency (alpha, 0 to 1), from
%a PNG (alpha channel) or an indexed GIF (transparent colour)
[image, map, pngAlpha] = imread(file);
if ~isempty(map)
    rgb = ind2rgb(image, map);
    info = imfinfo(file);
    alpha = ones(size(image));
    if isfield(info, "TransparentColor") && ~isempty(info(1).TransparentColor)
        alpha(image == info(1).TransparentColor - 1) = 0;
    end
else
    rgb = double(image) / double(intmax(class(image)));
    if isempty(pngAlpha)
        alpha = ones(size(image, 1), size(image, 2));
    else
        alpha = double(pngAlpha) / double(intmax(class(pngAlpha)));
    end
end
if size(rgb, 3) == 1
    rgb = repmat(rgb, 1, 1, 3);
end
end

function out = ResizeNearest(in, outSize)
%Nearest-neighbour resize - core MATLAB only
rows = min(size(in, 1), max(1, round(((1 : outSize(1)) - 0.5) * size(in, 1) / outSize(1) + 0.5)));
cols = min(size(in, 2), max(1, round(((1 : outSize(2)) - 0.5) * size(in, 2) / outSize(2) + 0.5)));
out = in(rows, cols, :);
end

function image = Blend(image, alpha, colour)
%Paint colour over the image, with per-pixel opacity alpha (0 to 1)
for c = 1 : 3
    image(:, :, c) = image(:, :, c) .* (1 - alpha) + colour(c) .* alpha;
end
end

function glyph = NumberGlyph(number, height)
%Anti-aliased mask (0 to 1) of a number in bold Arial, height pixels high.
%Rendered large in a hidden figure, then shrunk by averaging blocks of
%pixels - core MATLAB only
persistent cache
key = sprintf("n%d_%d", number, height);
if isstruct(cache) && isfield(cache, key)
    glyph = cache.(key);
    return
end

fig = figure(Visible="off", Units="pixels", Position=[100 100 400 400], Color="w", MenuBar="none", ToolBar="none");
closeFig = onCleanup(@() close(fig));
ax = axes(fig, Units="normalized", Position=[0 0 1 1], XLim=[0 1], YLim=[0 1], Visible="off");
text(ax, 0.5, 0.5, string(number), FontName="Arial", FontWeight="bold", FontUnits="pixels", FontSize=300, ...
    HorizontalAlignment="center", VerticalAlignment="middle", Color="k");
frame = getframe(fig);
mask = 1 - double(rgb2gray_(frame.cdata)) / 255;

%Crop to the digits, then shrink to the requested height
[r, c] = find(mask > 0.05);
mask = mask(min(r) : max(r), min(c) : max(c));
factor = max(1, round(size(mask, 1) / height));
mask = conv2(mask, ones(factor) / factor^2, "same");
glyph = mask(ceil(factor/2) : factor : end, ceil(factor/2) : factor : end);
glyph = min(max(glyph, 0), 1);
cache.(key) = glyph;
end

function g = rgb2gray_(rgb)
%Greyscale, without needing the Image Processing Toolbox
g = 0.299 * double(rgb(:, :, 1)) + 0.587 * double(rgb(:, :, 2)) + 0.114 * double(rgb(:, :, 3));
end
