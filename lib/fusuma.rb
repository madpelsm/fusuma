require_relative 'fusuma/version'
require_relative 'fusuma/action_stack'
require_relative 'fusuma/gesture_action'
require_relative 'fusuma/multi_logger'
require 'logger'
require 'open3'
require 'yaml'
require 'optparse'

# for debug
# require 'pry-byebug'

# this is top level module
module Fusuma
  # main class
  class Runner
    def self.run(args = {})
      debug = args.fetch(:v, false)
      MultiLogger.instance.debug_mode = true if debug
      instance = new
      MultiLogger.debug('Enable debug lines')
      instance.read_libinput
    end

    def read_libinput
      Open3.popen3(libinput_command) do |_i, o, _e, _w|
        o.each do |line|
          gesture_action = GestureAction.initialize_by(line, device_name)
          next if gesture_action.nil?
          @action_stack ||= ActionStack.new
          @action_stack.push gesture_action
          gesture_info = @action_stack.gesture_info
          trigger_keyevent(gesture_info) unless gesture_info.nil?
        end
      end
    end

    private

    def libinput_command
      # NOTE: --enable-dwt means "disable while typing"
      @libinput_command ||= "stdbuf -oL -- libinput-debug-events --device \
      /dev/input/#{device_name} --enable-dwt"
      MultiLogger.debug(libinput_command: @libinput_command)
      @libinput_command
    end

    def device_name
      return @device_name unless @device_name.nil?
      Open3.popen3('libinput-list-devices') do |_i, o, _e, _w|
        o.each do |line|
          MultiLogger.debug(line)
          extracted_input_device_from(line)
          next unless touch_is_available?(line)
          return @device_name
        end
      end
    end

    def extracted_input_device_from(line)
      return unless line =~ /^Kernel: /
      @device_name = line.match(/event[0-9]+/).to_s
    end

    def touch_is_available?(line)
      return false unless line =~ /^Tap-to-click: /
      return false if line =~ %r{n/a}
      true
    end

    def trigger_keyevent(gesture_info)
      case gesture_info.action_type
      when 'swipe'
        swipe(gesture_info.finger, gesture_info.direction)
      when 'pinch'
        pinch(gesture_info.direction)
      end
    end

    def swipe(finger, direction)
      shortcut = event_map['swipe'][finger.to_i][direction]['shortcut']
      `xdotool key #{shortcut}`
    end

    def pinch(direction)
      shortcut = event_map['pinch'][direction]['shortcut']
      `xdotool key #{shortcut}`
    end

    def event_map
      @event_map ||= YAML.load_file(config_file)
    end

    def config_file
      filename = 'fusuma/config.yml'
      original_path = File.expand_path "~/.config/#{filename}"
      default_path = File.expand_path "../#{filename}", __FILE__
      File.exist?(original_path) ? original_path : default_path
    end
  end
end
