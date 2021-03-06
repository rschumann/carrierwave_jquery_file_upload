# Ruby Deep Zoom Tools
#
# Convert images into the Deep Zoom Image (DZI) file format.
#
# DZI files can be rendered using any of the following software:
#  * Microsoft Silverlight Deep Zoom
#  * Microsoft Seadragon Ajax
#  * Microsoft Seadragon Mobile
#  * Microsoft Live Labs Pivot
#  * OpenZoom
#
# Requirements: rmagick gem (tested with version 2.9.0)
#
# Author:: MESO Web Scapes (www.meso.net)
# License:: MPL 1.1/GPL 3/LGPL 3
#
# Contributor(s):
#   Sascha Hanssen <hanssen@meso.net>
#   Daniel Gasienica <daniel@gasienica.ch>
#
# Software distributed under the License is distributed on an "AS IS" basis,
# WITHOUT WARRANTY OF ANY KIND, either express or implied. See the License
# for the specific language governing rights and limitations under the
# License.

class MosaicTiler 
  RMAGICK_ENABLE_MANAGED_MEMORY = true
  require "rubygems"
  require "RMagick"
  require  "fileutils"
  include Magick

  @queue = :mosaic_tiler_queue

  # Properties
  attr_accessor :image_quality, :tile_size, :tile_overlap, :tile_format, :copy_metadata

  @@tile_size = 372 
  @@tile_overlap = 0 
  @@tile_format = "jpg"
  @@image_quality = 0.7 
  @@copy_metadata = false 

  def self.perform(source,destination)
    # load image
    image = Magick::Image::read(source).first
    Rails.logger.debug( 'CREATE' )
    Rails.logger.debug( image.inspect )
     # remove image metadata if required
    image.strip! unless @@copy_metadata
    # store image dimensions
    Rails.logger.debug("store image dimensions columns #{image.columns} rows #{image.rows}")
    image_width, image_height = image.columns, image.rows
    # determine paths to files and directories
    image_basename, image_ext = splitext(File.basename(source))
    basename, ext = splitext(File.basename(destination))
    root_dir = File.dirname(destination)
    levels_root_dir = File.join(root_dir, basename + "_files")

    # auto select tile format if necessary
    @@tile_format = image_ext if @@tile_format == nil

    # iterate over all levels
    for level in [max_level(image_width, image_height),1]
      width, height = image.columns, image.rows
      Rails.logger.debug("level #{level} is #{width} x #{height}")

      current_level_dir = File.join(levels_root_dir, level.to_s)
      FileUtils.mkdir_p(current_level_dir)

      # iterate over columns
      x, col_count = 0, 0
      while x < width
        # iterate over rows
        y, row_count = 0, 0
        while y < height
          dest_path = File.join(current_level_dir, "#{col_count}_#{row_count}.#{@@tile_format}")
          tile_width, tile_height = tile_dimensions(x, y, @@tile_size, @@tile_overlap)
          #puts "tile_width #{tile_width} tile_height #{tile_height}"
          save_cropped_image(image, dest_path, x, y, tile_width, tile_height, @@image_quality * 100)
          y += (tile_height - (2 * @@tile_overlap))
          row_count += 1
        end
        x += (tile_width - (2 * @@tile_overlap))
        col_count += 1
      end
      image.resize!(0.096774)
    end

    # generate XML descriptor and write manifest file
    write_manifest_xml(destination,
                       :tile_size    => @@tile_size,
                       :tile_overlap => @@tile_overlap,
                       :tile_format  => @@tile_format,
                       :width        => image_width,
                       :height       => image_height)
  end


  # Debug: Given path to Deep Zoom Image (DZI) XML manifest,
  #        deletes manifest and tiles folder
  def self.delete(path)
    basename, ext = splitext(File.basename(path))
    root_dir = File.dirname(path)
    levels_root_dir = File.join(root_dir, basename + "_files")

    files_existed = (File.file?(path) or File.directory?(levels_root_dir))

    File.delete path if File.file? path
    FileUtils.remove_dir levels_root_dir if File.directory? levels_root_dir

    return files_existed
  end


protected
  # Determines width and height for tiles, dependent of tile position.
  # Center tiles have overlapping on each side.
  # Borders have no overlapping on the border side and overlapping on all other sides.
  # Corners have only overlapping on the right and lower border.
  def self.tile_dimensions(x, y, tile_size, tile_overlap)
    overlapping_tile_size = tile_size + (2 * tile_overlap)
    border_tile_size      = tile_size + tile_overlap

    tile_width  = (x > 0) ? overlapping_tile_size : border_tile_size
    tile_height = (y > 0) ? overlapping_tile_size : border_tile_size

    return tile_width, tile_height
  end

  # Calculates how often an image with given dimension can
  # be divided by two until 1x1 px are reached.
  def self.max_level(width, height)
    return (Math.log([width, height].max) / Math.log(2)).ceil
  end


  # Crops part of src image and writes it to dest path.
  #
  # Params: src: may be an Magick::Image object or a path to an image.
  #         dest: path where cropped image should be stored.
  #         x, y: offset from upper left corner of source image.
  #         width, height: width and height of cropped image.
  #         quality: compression level 0 - 100, lower number means higher compression.
  def self.save_cropped_image(src, dest, x, y, width, height, quality)
    if src.is_a? Magick::Image
      img = src
    else
      img = Magick::Image::read(src).first
    end

    # The crop method retains the offset information in the cropped image.
    # To reset the offset data, adding true as the last argument to crop.
    cropped = img.crop(x, y, width, height, true)
    cropped.write(dest) { self.quality = quality }
  end


  # Writes Deep Zoom XML manifest file
  def self.write_manifest_xml(path, properties)
    properties = { :xmlns => "http://schemas.microsoft.com/deepzoom/2008" }.merge properties
    xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>" +
          "<Image TileSize=\"#{properties[:tile_size]}\" Overlap=\"#{properties[:tile_overlap]}\" " +
           "Format=\"#{properties[:tile_format]}\" xmlns=\"#{properties[:xmlns]}\">" +
          "<Size Width=\"#{properties[:width]}\" Height=\"#{properties[:height]}\"/>" +
          "</Image>"

    open(path, "w") { |file| file.puts(xml) }
  end


  # Returns filename (without path and extension) and its extension as array.
  # path/to/file.txt -> ["file", "txt"]
  def self.splitext(path)
    extension = File.extname(path).gsub(".", "")
    filename  = File.basename(path, "." + extension)
    return filename, extension
  end
end


