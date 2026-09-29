# shrink

Make an image, video or PDF fit a size.

## Synopsis

```
shrink [options] file size
shrink -s size [options] file ...
```

## Description

A form takes uploads up to 2 MB. A chat app takes videos up to 25 MB. `shrink` writes a smaller copy of the file
that fits the size you give, and keeps as much quality as it can on the way.

```
photo.jpg -> photo-small.jpg (4.8MB -> 1.9MB, quality 85, 0.9s)
```

The copy goes beside the file as `name-small.ext`, or `name-small-1.ext` when that name is taken. The original is
never changed. When the file already fits, `shrink` says so and writes nothing.

Sizes read like `500K`, `25M` or `1.5G`, in steps of 1024. The target must be 1K or more.

Each kind of file has its own way down:

| Kind | Tool | How it gets smaller |
|---|---|---|
| Image | ImageMagick | Lower quality first, then a smaller width. |
| Video | ffmpeg | A bitrate worked out from the length, in two passes. |
| PDF | Ghostscript | Three presets, from the best looking to the smallest. |

`shrink` knows the kind from the ending. For a file without a known ending, it asks `file` what it holds.

## Options

| Option | What it does |
|---|---|
| `-s`, `--size SIZE` | The target, such as `500K` or `25M`. Use it to shrink many files to the same size. |
| `-w`, `--width PX` | The largest width, for images and video. Narrower files keep their width. |
| `-o`, `--out NAME` | Name the smaller copy yourself. Only with one file. |
| `-q`, `--quiet` | Show only the result line. |
| `-v`, `--verbose` | Show every setting it tries, and each real command before it runs. |
| `-h`, `--help` | Show the help. |

## Images

`shrink` strips the metadata from every image and turns it the right way up first. The metadata holds the camera,
the date and often the GPS position, and it can weigh 50 KB or more.

For JPEG, WebP, AVIF, HEIC and JPEG XL it then tries the qualities 85, 75, 65, 55 and 45 at full width, and keeps the
highest one that fits. When even 45 is too big, it tries 85%, 70%, 55%, 40%, 30%, 20% and 10% of the width, with the
same quality search at each one. PNG, GIF, TIFF and BMP have no quality setting, so only the width changes.

The result line says what it took, such as `quality 65, 55% wide`. The ending of the `-o` name picks the format,
so `-o photo.webp` converts a JPEG to WebP on the way. `-w 1920` caps the width before the search starts,
which suits photos from a phone that are 4000 pixels wide.

## Video

`shrink` reads the length of the clip and works out the bitrate that fills the target. It keeps 3% back for the
container and 96 kbit/s for the sound. Then ffmpeg encodes the clip twice. The first pass measures the clip and the
second one spends the bits where the picture needs them. That makes the size land close to the target.

When the copy still comes out too big, `shrink` tries once more at a lower bitrate. When that fails too, it writes
nothing.

| Ending | Video | Sound |
|---|---|---|
| `.mp4`, `.m4v`, `.mov`, `.mkv` | H.264, `-preset medium` | AAC 96k |
| `.webm` | VP9 | Opus 96k |
| anything else, such as `.avi` | H.264, and the copy ends in `.mp4` | AAC 96k |

A clip with no sound stays silent. `-w 1280` scales the video down as well, which looks better than a low bitrate
at full size. Below 50 kbit/s for the picture the result is not worth watching, so `shrink` stops and says the
target is too small for the length.

## PDF

Ghostscript rewrites the PDF with one of its presets. `shrink` tries them in order and stops at the first that fits.

| Preset | Images inside | Good for |
|---|---|---|
| `/printer` | 300 dpi | Printing. Often no smaller for text. |
| `/ebook` | 150 dpi | Reading on screen. |
| `/screen` | 72 dpi | The smallest. Scans turn soft. |

A PDF of plain text is mostly fonts, and no preset makes it much smaller. A scanned PDF is mostly images, and
shrinks a lot.

## Pass-through

Options after `--` go to `magick` for images, to both ffmpeg passes for video and to `gs` for PDF:

```console
$ shrink talk.mp4 25M -- -preset slow
$ shrink photo.jpg 500K -- -sampling-factor 4:2:0
$ shrink scan.pdf 2M -- -dColorImageResolution=100
```

`-preset slow` takes longer and gives a better picture at the same size.

## Needs

ImageMagick for images, ffmpeg for video and Ghostscript for PDF. You only need the one for the files you shrink.
`shrink` uses `magick` from ImageMagick 7, or `convert` from ImageMagick 6.

| Distro | Images | Video | PDF |
|---|---|---|---|
| Debian, Ubuntu | `imagemagick` | `ffmpeg` | `ghostscript` |
| Fedora | `ImageMagick` | `ffmpeg-free` | `ghostscript` |
| Arch | `imagemagick` | `ffmpeg` | `ghostscript` |
| openSUSE | `ImageMagick` | `ffmpeg-7` | `ghostscript` |
| Alpine | `imagemagick` | `ffmpeg` | `ghostscript` |

## Examples

### A photo for a form

```console
$ shrink photo.jpg 500K
photo.jpg -> photo-small.jpg (4.8MB -> 488KB, quality 75, 55% wide, 3.2s)
```

### Every photo in a folder, no wider than 1920

```console
$ shrink -s 1M -w 1920 *.jpg
IMG_4410.jpg -> IMG_4410-small.jpg (5.1MB -> 702KB, quality 85, 0.8s)
IMG_4411.jpg -> IMG_4411-small.jpg (4.6MB -> 655KB, quality 85, 0.8s)
beach.jpg is already 610KB, which fits 1MB. Nothing written.
```

### A screen recording for chat

```console
$ shrink -v demo.mp4 25M
shrink: demo.mp4: video, 3:10, 148MB
shrink: bitrate: 25MB over 190s, less 96k for sound, is 974k
+ ffmpeg -nostdin -y -hide_banner -loglevel error -i demo.mp4 -c:v libx264 -preset medium -b:v 974k -pass 1 -passlogfile ./.shrink-Xq2c9L/pass -an -f null /dev/null
+ ffmpeg -nostdin -y -hide_banner -loglevel error -i demo.mp4 -c:v libx264 -preset medium -b:v 974k -pass 2 -passlogfile ./.shrink-Xq2c9L/pass -c:a aac -b:a 96k -movflags +faststart demo-small.mp4
demo.mp4 -> demo-small.mp4 (148MB -> 24MB, 974k, 2 passes, 1m52s)
```

### A scanned PDF

```console
$ shrink scan.pdf 4K
shrink: scan.pdf: /printer gives 10KB, trying the next
scan.pdf -> scan-small.pdf (5.9KB -> 3.1KB, /ebook, 0.1s)
```

### A target out of reach

```console
$ shrink -v scan.pdf 1K
+ gs -q -dNOPAUSE -dBATCH -dSAFER -sDEVICE=pdfwrite -dCompatibilityLevel=1.4 -dPDFSETTINGS=/printer -sOutputFile=./.shrink-cz0B8F/try.pdf scan.pdf
shrink: scan.pdf: /printer gives 10KB, trying the next
+ gs -q -dNOPAUSE -dBATCH -dSAFER -sDEVICE=pdfwrite -dCompatibilityLevel=1.4 -dPDFSETTINGS=/ebook -sOutputFile=./.shrink-cz0B8F/try.pdf scan.pdf
shrink: scan.pdf: /ebook gives 3.1KB, trying the next
+ gs -q -dNOPAUSE -dBATCH -dSAFER -sDEVICE=pdfwrite -dCompatibilityLevel=1.4 -dPDFSETTINGS=/screen -sOutputFile=./.shrink-cz0B8F/try.pdf scan.pdf
shrink: scan.pdf: /screen gives 3.1KB, over 1KB
shrink: wrote nothing. The smallest Ghostscript gets for scan.pdf is 3.1KB, with /ebook
```

### Already small enough

```console
$ shrink scan.pdf 1M
scan.pdf is already 5.9KB, which fits 1MB. Nothing written.
```

## Troubleshooting

`shrink: wrote nothing. The smallest ImageMagick gets for X is S, at 10% wide`
: The target is too small for that image even at a tenth of its width. Try a larger target, or another format
  such as WebP with `-o photo.webp`.

`shrink: 1MB is too small for 9:42 of video, it leaves under 50k a second for the picture`
: Cut the clip first, or ask for more room. As a guide, 1 minute of 720p video looks fine at about 10 MB.

`shrink: X is not an image, a video or a PDF`
: The ending is unknown and `file` did not recognise the content either.

The copy of a PNG screenshot is blurry
: PNG has no quality setting, so `shrink` had to make it narrower. Try `-o shot.webp` or `-o shot.jpg`. Both come out
  much smaller at full width.

## Exit status

| Code | Meaning |
|---|---|
| 0 | Every file fits, either as a new copy or as it was. |
| 1 | It failed, or a file could not reach the target. Nothing was written for that file. |
| 2 | Bad usage, such as no target size. |
| 3 | The tool for that kind of file is missing. |
| 4 | Refused. The `-o` name is taken. |

## See also

`togif`, `magick(1)`, `ffmpeg(1)`, `gs(1)`
