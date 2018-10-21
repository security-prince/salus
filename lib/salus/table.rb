require_relative 'color'

module Salus
  module Table
    include Color

    BORDER = {
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

    def tabulate(headings, table)
      table = [headings] + table

      columns = table.map(&:length).max

      # Find, for all columns, the maximum length of any cell in that column;
      # make sure to handle the case that a row is missing some columns
      max_lengths = (0...columns).map do |index|
        table
          .map { |row| index < row.length ? uncolorize(row[index]).length : -1 }
          .max
      end

      # Pad every table cell with one space on the left, and with enough space
      # on the right to match the longest element in its column
      rows = table.each_with_index.map do |row, _row_index|
        cells = (0...columns).map do |column_index|
          next ' ' * (max_lengths[column_index] + 2) if column_index >= row.length

          string = row[column_index]
          length = uncolorize(string).length
          right_padding = 1 + max_lengths[column_index] - length

          ' ' + string + (' ' * right_padding)
        end

        BORDER[:vertical] + cells.join(BORDER[:vertical]) + BORDER[:vertical]
      end

      top_border =
        BORDER[:top_left] +
        max_lengths.map { |width| BORDER[:horizontal] * (width + 2) }.join(BORDER[:top_mid]) +
        BORDER[:top_right]

      header_bottom_border =
        BORDER[:left_mid] +
        max_lengths.map { |width| BORDER[:horizontal] * (width + 2) }.join(BORDER[:cross]) +
        BORDER[:right_mid]

      bottom_border =
        BORDER[:bottom_left] +
        max_lengths.map { |width| BORDER[:horizontal] * (width + 2) }.join(BORDER[:bottom_mid]) +
        BORDER[:bottom_right]

      # Add some horizontal lines
      rows.insert(0, top_border)
      rows.insert(2, header_bottom_border)
      rows.push(bottom_border)

      rows.join("\n")
    end
  end
end
