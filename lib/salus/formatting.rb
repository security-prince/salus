module Salus
  module Formatting
    COLOR_CODES = {
      red:    31,
      green:  32,
      yellow: 33
    }.freeze

    TABLE_BORDER_CHARS = {
      top_mid:      '┬',
      top_left:     '┌',
      top_right:    '┐',
      bottom_mid:   '┴',
      bottom_left:  '└',
      bottom_right: '┘',
      left_mid:     '├',
      right_mid:    '┤',
      horizontal:   '─',
      vertical:     '│',
      cross:        '┼'
    }.freeze

    def colorize(string, color)
      return string if color.nil?
      "\e[#{COLOR_CODES.fetch(color)}m#{string}\e[0m"
    end

    def uncolorize(string)
      string.gsub(/#{'\e'}\[(\d+)m/, '')
    end

    def tabulate(headers, table)
      # For brevity
      chars = TABLE_BORDER_CHARS

      # Squish the headers into the same structure as the table;
      # stringify everything
      table = [headers.map(&:to_s)] + table.map { |row| row.map(&:to_s) }

      n_rows = table.length
      n_columns = table.map(&:length).max

      # Find, for all columns, the maximum length of any cell in that column;
      # make sure to handle the case that a row is missing some columns.
      # Remove any coloring codes from each cell before taking the length
      max_lengths = (0...n_columns).map do |index|
        lengths = table.map do |row|
          next -1 if index >= row.length
          uncolorize(row[index]).length
        end

        lengths.max
      end

      # For any given column, the longest cell gets padded with one space on the
      # left and one the right; the other cells are padded with one space on the
      # left, and sufficiently many spaces on the right to match the longest cell
      # in length. If a given row is missing some column, just fill the cell
      # with sufficiently many spaces to match the longest cell

      rows = table.map do |row|
        cells = (0...n_columns).map do |index|
          next ' ' * (max_lengths[column_index] + 2) if column_index >= row.length

          string = row[index]
          length = uncolorize(string).length
          right_padding = 1 + max_lengths[index] - length

          ' ' + string + (' ' * right_padding)
        end

        # Construct the stringified row, including the outer borders
        chars[:vertical] + cells.join(chars[:vertical]) + chars[:vertical]
      end

      # Construct the top border, the border between headers and content,
      # and the bottom border

      top_border =
        chars[:top_left] +
        max_lengths.map { |length| chars[:horizontal] * (length + 2) }.join(chars[:top_mid]) +
        chars[:top_right]

      header_bottom_border =
        chars[:left_mid] +
        max_lengths.map { |length| chars[:horizontal] * (length + 2) }.join(chars[:cross]) +
        chars[:right_mid]

      bottom_border =
        chars[:bottom_left] +
        max_lengths.map { |length| chars[:horizontal] * (length + 2) }.join(chars[:bottom_mid]) +
        chars[:bottom_right]

      # Splice the borders into the content, and construct the final stringified table
      [
        top_border,
        rows[0],
        header_bottom_border,
        rows[(1...n_rows)],
        bottom_border
      ].join("\n")
    end
  end
end
