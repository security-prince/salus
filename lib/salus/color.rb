module Salus
  module Color
    COLOR_CODES = {
      red: 31,
      green: 32,
      yellow: 33
    }.freeze

    def colorize(string, color)
      return string if color.nil?
      "\e[#{COLOR_CODES.fetch(color)}m#{string}\e[0m"
    end

    def uncolorize(string)
      string.gsub(/#{'\e'}\[(\d+)m/, '')
    end
  end
end
