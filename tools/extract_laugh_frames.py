"""Extract the original laughter clip without removing the pale belly.

Development-only dependencies: av, numpy, pillow. The desktop player has none.
Usage: python tools/extract_laugh_frames.py original.mp4 --output desktop/assets/laugh
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import av
import numpy as np
from PIL import Image, ImageFilter


def connected_mask(binary: np.ndarray, *, background: bool) -> np.ndarray:
    """Use scanline components; keep border background or largest foreground."""
    parents, areas, borders, runs = [], [], [], []
    previous = []

    def find(index):
        while parents[index] != index:
            parents[index] = parents[parents[index]]
            index = parents[index]
        return index

    height, width = binary.shape
    for y, row in enumerate(binary):
        edges = np.flatnonzero(np.diff(np.r_[False, row, False].astype(np.int8)))
        current = []
        cursor = 0
        for start, end in zip(edges[::2], edges[1::2]):
            index = len(parents)
            parents.append(index)
            areas.append(int(end - start))
            borders.append(y == 0 or y == height - 1 or start == 0 or end == width)
            current.append((int(start), int(end), index))
            runs.append((y, int(start), int(end), index))
            while cursor < len(previous) and previous[cursor][1] <= start:
                cursor += 1
            adjacent = cursor
            while adjacent < len(previous) and previous[adjacent][0] < end:
                left, right = find(index), find(previous[adjacent][2])
                if left != right:
                    parents[right] = left
                    areas[left] += areas[right]
                    borders[left] = borders[left] or borders[right]
                adjacent += 1
        previous = current
    mask = np.zeros(binary.shape, dtype=np.uint8)
    if not parents:
        return mask
    largest = max(range(len(parents)), key=lambda i: areas[i] if parents[i] == i else 0)
    for y, start, end, index in runs:
        component = find(index)
        if borders[component] if background else component == largest:
            mask[y, start:end] = 255
    return mask


def extract_character(rgb: Image.Image) -> tuple[Image.Image, dict]:
    """Separate neutral background while preserving warm cream skin and eyes."""
    pixels = np.asarray(rgb).astype(np.int16)
    chroma = pixels.max(axis=2) - pixels.min(axis=2)
    neutral = ((chroma <= 22) & (pixels.min(axis=2) > 110)) | (pixels.min(axis=2) > 248)
    exterior = connected_mask(neutral, background=True)
    alpha = np.where(exterior != 0, 0, 255).astype(np.uint8)
    # The source floor can enclose a white region between the feet. Below the
    # head, neutral white/gray pixels are floor, while the cream belly stays warm.
    lower_floor = neutral.copy()
    lower_floor[: round(rgb.height * 0.60), :] = False
    alpha[lower_floor] = 0
    alpha = connected_mask(alpha != 0, background=False)
    # Verify actual source body pixels, including the pale belly, in every frame.
    warm_body = ((pixels[:, :, 0] - pixels[:, :, 2] >= 40)
                 & (pixels[:, :, 1] - pixels[:, :, 2] >= 15))
    missing_warm = int(np.count_nonzero(warm_body & (alpha == 0)))
    warm_count = int(np.count_nonzero(warm_body))
    if warm_count and missing_warm / warm_count > 0.002:
        raise ValueError(f"Foreground loss: {missing_warm}/{warm_count} source body pixels")
    coverage = Image.fromarray(alpha).filter(ImageFilter.GaussianBlur(0.45))
    result = rgb.convert('RGBA')
    result.putalpha(coverage)
    return result, {'warm_body_pixels': warm_count, 'missing_warm_pixels': missing_warm}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('video', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    report = {'frame_count': 0, 'minimum_warm_body_retention': 1.0,
              'canvas': [384, 416], 'clipped_frames': [], 'source_fps': None}
    with av.open(str(args.video)) as container:
        report['source_fps'] = str(container.streams.video[0].average_rate)
        for index, frame in enumerate(container.decode(video=0)):
            rgb = frame.to_image()
            # Wider, stable registration across every pose, including falling.
            box = (round(rgb.width * 0.23), round(rgb.height * 0.06),
                   round(rgb.width * 0.76), round(rgb.height * 0.98))
            cropped = rgb.crop(box)
            character, stats = extract_character(cropped)
            bounds = character.getchannel('A').point(lambda a: 255 if a > 16 else 0).getbbox()
            if not bounds:
                raise ValueError(f'Empty frame {index}')
            if bounds[0] <= 1 or bounds[1] <= 1 or bounds[2] >= cropped.width - 1 or bounds[3] >= cropped.height - 1:
                report['clipped_frames'].append(index)
            # Preserve the previous player scale/ground position. The wider
            # source crop is a safety margin, not a reason to shrink the body.
            ratio = 377 / (rgb.height * (870 / 1080))
            scaled = character.resize((round(cropped.width * ratio), round(cropped.height * ratio)), Image.Resampling.LANCZOS)
            canvas = Image.new('RGBA', (384, 416))
            position = (round(7 + (box[0] - rgb.width * (540 / 1920)) * ratio),
                        round(19 + (box[1] - rgb.height * (165 / 1080)) * ratio))
            canvas.alpha_composite(scaled, position)
            visible = canvas.getchannel('A').point(lambda a: 255 if a > 16 else 0).getbbox()
            if not visible or visible[0] <= 1 or visible[1] <= 1 or visible[2] >= 383 or visible[3] >= 415:
                raise ValueError(f'Player canvas clips frame {index}')
            data = np.array(canvas)
            # Remove the weakly tinted floor matte under the feet. Limit this
            # to the ground area; never classify the pale abdomen by whiteness.
            color = data[:, :, :3].astype(np.int16)
            floor_matte = ((color.max(axis=2) - color.min(axis=2) < 40)
                           & (color.min(axis=2) > 140))
            floor_matte[:340, :] = False
            data[floor_matte, 3] = 0
            data[data[:, :, 3] < 4] = 0
            canvas = Image.fromarray(data)
            canvas.save(args.output / f'{index:04d}.png')
            retention = 1 - stats['missing_warm_pixels'] / max(1, stats['warm_body_pixels'])
            report['minimum_warm_body_retention'] = min(report['minimum_warm_body_retention'], retention)
            report['frame_count'] += 1
            if index % 60 == 0:
                print(f'Processed frame {index}', flush=True)
    if report['clipped_frames']:
        raise ValueError(f"Source crop clips frames: {report['clipped_frames']}")
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(report), flush=True)


if __name__ == '__main__':
    main()
