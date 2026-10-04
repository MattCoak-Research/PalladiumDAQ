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
%   * Tolerance  - fraction of pixels that may differ from an existing
%                  file without it being rewritten, for images that vary a
%                  little from run to run (e.g. plots of simulated data).
%                  Default 0
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
end

HighlightColour = [0.85 0.33 0.10];    %Orange, as the docs' headings

%Let the window finish drawing, then export its contents
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
