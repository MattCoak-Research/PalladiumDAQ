function BuildGettingStarted(mdFile, mFile, version)
%BUILDGETTINGSTARTED - Convert the Getting Started guide's Markdown source into a plain-text live script.
%
%   BuildGettingStarted(mdFile, mFile, version) reads mdFile (e.g.
%   DocsSrc/GettingStarted.md) and writes mFile (e.g. Docs/GettingStarted.m), a
%   live script in MATLAB's plain-text Live Code format that opens formatted
%   in the Live Editor. It is the toolbox's Getting Started guide.
%
%   The Markdown source supports:
%   * Headings (# and ##), paragraphs (wrapped lines are joined), and
%     "- " bulleted lists. **bold**, *italic*, `code` and [links](...),
%     including matlab: links, pass through unchanged
%   * {{version}}, replaced by version
%   * Images, ![alt](path), with path relative to mdFile. They are embedded in
%     the live script, so need not ship with it. An optional {width=N} straight
%     after the image sets its displayed width (height keeps the aspect ratio)
%   * A trailing {align=center} on a line, to centre it
%   * ```matlab fenced blocks, which become runnable code
%   * --- on its own line, which starts a new section (%% break)
%   * <!-- HTML comments -->, which are left out

arguments
    mdFile (1,1) string
    mFile (1,1) string
    version (1,1) string
end

mdFolder = fileparts(mdFile);
source = replace(fileread(mdFile, Encoding="UTF-8"), "{{version}}", version);
source = regexprep(source, "<!--.*?-->", "");   %Drop comments
mdLines = splitlines(string(source));

body = strings(0);
images = struct("Id", {}, "File", {}, "Width", {});
paragraph = "";     %Text of the paragraph or list item being built up
inCode = false;

for line = mdLines'
    trimmed = strtrim(line);

    %Fenced code blocks become live script code
    if startsWith(trimmed, "```")
        [body, paragraph] = Flush(body, paragraph);
        inCode = ~inCode;
        continue
    end
    if inCode
        body(end+1) = strip(line, "right"); %#ok<AGROW>
        continue
    end

    %A blank line ends the paragraph; a heading, bullet or section break
    %starts a new one; anything else continues it
    if trimmed == ""
        [body, paragraph] = Flush(body, paragraph);
    elseif trimmed == "---"
        [body, paragraph] = Flush(body, paragraph);
        body(end+1) = "%%"; %#ok<AGROW>
    elseif startsWith(trimmed, ["#", "- "])
        [body, ~] = Flush(body, paragraph);
        paragraph = trimmed;
    elseif paragraph == ""
        paragraph = trimmed;
    else
        paragraph = paragraph + " " + trimmed;
    end
end
[body, ~] = Flush(body, paragraph);

%Swap each image for a reference to an appendix entry holding its data
for i = 1 : numel(body)
    [tokens, matches] = regexp(body(i), "!\[([^\]]*)\]\(([^)]+)\)(\{width=\d+\})?", "tokens", "match");
    for k = 1 : numel(tokens)
        images(end+1).Id = sprintf("%04x", numel(images) + 1); %#ok<AGROW>
        images(end).File = fullfile(mdFolder, tokens{k}(2));
        images(end).Width = NaN;
        if numel(tokens{k}) == 3 && tokens{k}(3) ~= ""     %The optional {width=N}
            images(end).Width = str2double(extractBetween(tokens{k}(3), "=", "}"));
        end
        body(i) = replace(body(i), matches(k), "![" + tokens{k}(1) + "](text:image:" + images(end).Id + ")");
    end
end

%Live scripts end with a blank line, then the appendix
lines = [body, "", ...
    "%[appendix]{""version"":""1.0""}", "%---", ...
    "%[metadata:view]", "%   data: {""layout"":""inline""}", "%---"];
for image = images
    lines = [lines, "%[text:image:" + image.Id + "]", "%   data: " + ImageData(image), "%---"]; %#ok<AGROW>
end
writelines(lines, mFile, Encoding="UTF-8");
end

function [body, paragraph] = Flush(body, paragraph)
%Write out the paragraph being built up, as a %[text] line - centred if it
%ends with {align=center}
if paragraph == ""
    return
end
if endsWith(paragraph, "{align=center}")
    paragraph = strtrim(extractBefore(paragraph, strlength(paragraph) - strlength("{align=center}") + 1));
    body(end+1) = "%[text]{""align"":""center""} " + paragraph;
else
    body(end+1) = "%[text] " + paragraph;
end
paragraph = "";
end

function data = ImageData(image)
%Appendix data for an image: its size and base64-encoded contents
assert(isfile(image.File), "BuildGettingStarted:ImageNotFound", "Image not found: %s", image.File);
info = imfinfo(image.File);
width = info.Width;
height = info.Height;
if ~isnan(image.Width)
    height = round(height * image.Width / width);
    width = image.Width;
end

[~, ~, ext] = fileparts(image.File);
mimeType = replace(lower(extractAfter(ext, ".")), "jpg", "jpeg");
fid = fopen(image.File, "r");
bytes = fread(fid, Inf, "*uint8");
fclose(fid);

data = "{""align"":""baseline"",""height"":" + height + ",""src"":""data:image\/" + mimeType + ";base64," + ...
    matlab.net.base64encode(bytes) + """,""width"":" + width + "}";
end
