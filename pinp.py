#!/usr/bin/env python3
"""
Picture in Picture.

Usage:
  pinp <background_video> <overlay_video> <new_video> [--ratio=<ratio>] [--sync=<sync>] [--position=<position>]

Options:
  -h --help                 Show this screen.
  -r --ratio=<ratio>        The ratio of width of background video to use for resizing overlay_video [default: 0.25].
  -s --sync=<sync>          Pair of seconds x,y for which background_video is sync with overlay_video [default: 0,0].
  -p --position=<position>  The position of the overlay (top-left, top-right, bottom-left or bottom-right) [default: top-left].
"""

"""
Shell requirements:
  - ffmpeg
  - ffprobe

Python requirements:
  - docopt
"""

from docopt import docopt
import os
import json
from fractions import Fraction

class VideoMetadata(object):
  def __init__(self, width, height, sample_aspect_ratio=Fraction(1,1)):
    self.width=width
    self.height=height
    self.sample_aspect_ratio = sample_aspect_ratio

  def ratio(self):
    return Fraction(self.width, self.height) * self.sample_aspect_ratio

  def width_scale(self, scale_ratio):
    new_width = self.width*scale_ratio
    new_height = new_width * self.ratio().denominator / self.ratio().numerator
    return VideoMetadata(int(new_width), int(new_height))
  
  @staticmethod
  def from_json(json_dict):
    if 'sample_aspect_ratio' in json_dict.keys():
      sample_aspect_ratio = list(map(int, json_dict['sample_aspect_ratio'].split(':')))
    else:
      sample_aspect_ratio = 1,1
    return VideoMetadata(
      int(json_dict['width']),
      int(json_dict['height']),
      Fraction(sample_aspect_ratio[0], sample_aspect_ratio[1]))

class Position(object):
  @staticmethod
  def cmd_name():
    raise NotImplementedError

  def compute_background_position(self, background_meta, overlay_meta):
    raise NotImplementedError

class TopLeft(Position):
  @staticmethod
  def cmd_name():
    return 'top-left'

  def compute_background_position(self, background_meta, overlay_meta):
    return 0, 0

class TopRight(Position):
  @staticmethod
  def cmd_name():
    return 'top-right'
  
  def compute_background_position(self, background_meta, overlay_meta):
    return (background_meta.width - overlay_meta.width), 0

class BottomLeft(Position):
  @staticmethod
  def cmd_name():
    return 'bottom-left'
  
  def compute_background_position(self, background_meta, overlay_meta):
    return 0, (background_meta.height - overlay_meta.height)

class BottomRight(Position):
  @staticmethod
  def cmd_name():
    return 'bottom-right'
  
  def compute_background_position(self, background_meta, overlay_meta):
    return (background_meta.width - overlay_meta.width), (background_meta.height - overlay_meta.height)

class NotFound(Exception):
  pass

def detect(iterable, condition_lambda):
  toReturn = next((x for x in iterable if condition_lambda(x)), None)
  if toReturn == None:
    raise NotFound()
  return toReturn

def is_valid_position(position_string):
  return position_string in ["top-left", "top-right", "bottom-left", "bottom-right"]

def check_arguments(arguments):
  arguments['--ratio'] = float(arguments['--ratio'])
  assert 0 < arguments['--ratio'] and arguments['--ratio'] <= 1.0

  arguments['--sync'] = list(map(int, arguments['--sync'].split(',')))
  # TODO

  assert is_valid_position(arguments['--position'])

def extract_metadata(filename):
  metadata_raw = os.popen('ffprobe -v quiet -print_format json -show_format -show_streams '+filename).read()
  metadata_json = json.loads(metadata_raw)
  stream_dict = detect(metadata_json['streams'], lambda stream : stream['codec_type'] == 'video')
  return VideoMetadata.from_json(stream_dict)

def apply_ffmpeg_overlay(
  background_filename,
  overlay_filename,
  resized_overlay_meta,
  overlay_position,
  new_video_filename):
  ffmpeg_cmd = "ffmpeg -hide_banner -loglevel panic -i "
  ffmpeg_cmd += background_filename
  ffmpeg_cmd += " -i "
  ffmpeg_cmd += overlay_filename
  ffmpeg_cmd += " -filter_complex \"[1] scale="
  ffmpeg_cmd += str(resized_overlay_meta.width)
  ffmpeg_cmd += ":"
  ffmpeg_cmd += str(resized_overlay_meta.height)
  ffmpeg_cmd += " [over]; [0][over] overlay="
  ffmpeg_cmd += str(overlay_position[0])
  ffmpeg_cmd += ":"
  ffmpeg_cmd += str(overlay_position[1])
  ffmpeg_cmd += "\" "
  ffmpeg_cmd += new_video_filename
  print(ffmpeg_cmd)
  os.system(ffmpeg_cmd)

if __name__ == '__main__':
  arguments = docopt(__doc__, version='Picture in Picture 1.0')
  check_arguments(arguments)
  background_meta = extract_metadata(arguments['<background_video>'])
  print("Background width,height : " + str(background_meta.width) + "," + str(background_meta.height))
  overlay_meta = extract_metadata(arguments['<overlay_video>'])
  print("Overlay width,height : " + str(overlay_meta.width) + "," + str(overlay_meta.height))
  new_video_meta = background_meta
  resized_overlay_meta = overlay_meta.width_scale(arguments['--ratio'])
  print("Resized width,height : " + str(resized_overlay_meta.width) + "," + str(resized_overlay_meta.height))
  positionStrategy = detect(Position.__subclasses__(), lambda strategy : strategy.cmd_name() == arguments['--position'])()
  position = positionStrategy.compute_background_position(background_meta, resized_overlay_meta)
  print("Overlay position : " + str(position))
  apply_ffmpeg_overlay(
    arguments['<background_video>'],
    arguments['<overlay_video>'],
    resized_overlay_meta,
    position,
    arguments['<new_video>'])