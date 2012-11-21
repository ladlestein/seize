require 'csv'

module Seize

  module Job

    NO_OBJECT_FOUND = "no object found (presumably a failed update)"

    def import_file(source_file, reject_file, error_file, encoding = "UTF-8", headers = false)
      csv = CSV.new(source_file, {:encoding => encoding, :headers => headers, :return_headers => false})

      csv.each do | row |
        begin
          object = yield row

          if ENV["RAILS_ENV"] != 'test' && ENV["RAILS_ENV"] != 'production'
            puts CSV.generate_line(row, :encoding => encoding)
          end
          if object.nil?
            error_file.puts NO_OBJECT_FOUND
            reject_file.puts CSV.generate_line(row, :encoding => encoding)
          elsif object.valid?
            object.save!
          else
            reject_file.puts CSV.generate_line(row, :encoding => encoding)
            error_file.puts object.errors.full_messages.join(" | ")
          end
        rescue ActiveRecord::RecordInvalid => e
          reject_file.puts CSV.generate_line(row, :encoding => encoding)
          error_file.puts e
        end

      end
      reject_file.close
      error_file.close
    end

  end

end
