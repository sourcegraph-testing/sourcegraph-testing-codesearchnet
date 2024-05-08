# encoding: utf-8
# Copyright (c) 2011-2013 Hongli Lai
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

require 'mizuho/fuzzystringmatch'
require 'mizuho/utils'

module Mizuho

class IdMap
	class AlreadyAssociatedError < StandardError
	end

	include Utils

	URANDOM = File.open("/dev/urandom", "rb")
	MATCHER = JaroWinklerPure.new
	BANNER =
		"###### Autogenerated by Mizuho, DO NOT EDIT ######\n" <<
		"# This file maps section names to IDs so that the commenting system knows which\n" <<
		"# comments belong to which section. Section names may be changed at will but\n" <<
		"# IDs always stay the same, allowing one to retain old comments even if you\n" <<
		"# rename a section.\n" <<
		"#\n" <<
		"# This file is autogenerated but is not a cache; you MUST NOT DELETE this\n" <<
		"# file and you must check it into your version control system. If you lose\n" <<
		"# this file you may lose the ability to identity old comments.\n" <<
		"#\n" <<
		"# Entries marked with \"fuzzy\" indicate that the section title has changed\n" <<
		"# and that Mizuho has found an ID which appears to be associated with that\n" <<
		"# section. You should check whether it is correct, and if not, fix it.\n\n"

	attr_reader :entries, :associations

	def initialize
		@entries = {}
		@associations = {}
		#@namespace = slug(File.basename(filename, File.extname(filename)))
	end

	def load(filename_or_io)
		@entries.clear
		open_io(filename_or_io, :read) do |io|
			fuzzy = false
			while true
				begin
					line = io.readline.strip
					if line.empty?
						fuzzy = false
					elsif line == "# fuzzy"
						fuzzy = true
					elsif line !~ /\A#/
						title, id = line.split("\t=>\t", 2)
						add(title, id, fuzzy, false)
						fuzzy = false
					end
				rescue EOFError
					break
				end
			end
		end
		return self
	end

	def save(filename_or_io)
		normal, orphaned = group_and_sort_entries
		output = ""
		output << BANNER
		normal.each do |entry|
			output << "# fuzzy\n" if entry.fuzzy?
			output << "#{entry.title}	=>	#{entry.id}\n"
			output << "\n"
		end
		if !orphaned.empty?
			output << "\n"
			output << "### These sections appear to have been removed. Please check.\n"
			output << "\n"
			orphaned.each do |entry|
				output << "# fuzzy\n" if entry.fuzzy?
				output << "#{entry.title}	=>	#{entry.id}\n"
				output << "\n"
			end
		end
		open_io(filename_or_io, :write) do |f|
			f.write(output)
		end
	end

	def generate_associations(titles)
		@associations = {}

		# Associate exact matches.
		titles = titles.reject do |title|
			if (entry = @entries[title]) && !entry.associated?
				entry.associated = true
				@associations[title] = entry.id
				true
			else
				false
			end
		end

		# For the remaining titles, associate with moved or similar-looking entry.
		titles.reject! do |title|
			if entry = find_moved(title)
				@entries.delete(entry.title)
				@entries[title] = entry
				entry.title = title
				entry.associated = true
				entry.fuzzy = false
				@associations[title] = entry.id
				true
			else
				false
			end
		end

		# For the remaining titles, associate with similar-looking entry.
		titles.reject! do |title|
			if entry = find_similar(title)
				@entries.delete(entry.title)
				@entries[title] = entry
				entry.title = title
				entry.associated = true
				entry.fuzzy = true
				@associations[title] = entry.id
				true
			else
				false
			end
		end

		# For the remaining titles, create new entries.
		titles.each do |title|
			id = create_unique_id(title)
			add(title, id, false, true)
			@associations[title] = id
		end
	end
	
	def xassociate(title)
		if entry = @entries[title]
			if entry.associated?
				raise AlreadyAssociatedError, "Cannot associate an already associated title (#{title.inspect})"
			else
				entry.associated = true
				id = entry.id
			end
		elsif (moved_entry = find_moved(title)) || (similar_entry = find_similar(title))
			if moved_entry
				puts "moved entry: #{title.inspect} -> #{moved_entry.title.inspect}"
			elsif similar_entry
				puts "similar entry: #{title.inspect} -> #{similar_entry.title.inspect}"
			end
			entry = (moved_entry || similar_entry)
			@entries.delete(entry.title)
			@entries[title] = entry
			entry.title = title
			entry.associated = true
			entry.fuzzy = true if similar_entry
			id = entry.id
		else
			id = create_unique_id(title)
			add(title, id, false, true)
		end
		return id
	end

	def add(title, id, *options)
		return @entries[title] = Entry.new(title, id || create_unique_id(title), *options)
	end

	def stats
		fuzzy = 0
		orphaned = 0
		@entries.each_value do |entry|
			fuzzy += 1 if entry.fuzzy?
			orphaned += 1 if !entry.associated?
		end
		return { :fuzzy => fuzzy, :orphaned => orphaned }
	end

private
	# fuzzy
	#   Whether #associate has fuzzily associated a title with this entry.
	#
	# associated
	#   Whether #associate has associated a title with this entry.
	#   Immediately after loading a map file, all entries are marked
	#   as 'not associated'.
	class Entry < Struct.new(:title, :id, :fuzzy, :associated)
		alias fuzzy? fuzzy
		alias associated? associated
		
		def <=>(other)
			if (a = Utils.extract_chapter(title)) &&
			   (b = Utils.extract_chapter(other.title))
				# Sort by chapter whenever possible.
				a[0] = Utils.chapter_to_int_array(a[0])
				b[0] = Utils.chapter_to_int_array(b[0])
				return a <=> b
			else
				return title <=> other.title
			end
		end
	end

	def find_moved(title)
		orig_chapter, orig_pure_title = extract_chapter(title)
		return nil if !orig_chapter

		# Find all possible matches.
		orig_chapter_digits = chapter_to_int_array(orig_chapter)
		matches = []
		@entries.each_value do |entry|
			next if entry.associated?
			chapter, pure_title = extract_chapter(entry.title)
			if chapter && orig_pure_title == pure_title
				matches << {
					:chapter_digits => chapter_to_int_array(chapter),
					:pure_title => pure_title,
					:entry => entry
				}
			end
		end

		# Iterate until we find the best match. We match the chapter
		# digits from left to right.
		digit_match_index = 0
		while matches.size > 1
			orig_digit = orig_chapter_digits[digit_match_index] || 1

			# Find closest digit in all matches.
			tmp = matches.min do |a, b|
				x = a[:chapter_digits][digit_match_index] - orig_digit
				y = b[:chapter_digits][digit_match_index] - orig_digit
				x.abs <=> y.abs
			end
			closest_digit = tmp[:chapter_digits][digit_match_index]

			# Filter out all matches with this digit.
			matches = matches.find_all do |m|
				m[:chapter_digits][digit_match_index] == closest_digit
			end

			# If a next iteration is necessary, we check the next digit.
			digit_match_index += 1
		end

		if matches.empty?
			return nil
		else
			return matches[0][:entry]
		end
	end
	
	def find_similar(title)
		lower_title = title.downcase
		best_score = nil
		best_match = nil
		@entries.each_value do |entry|
			next if entry.associated?
			score = MATCHER.getDistance(entry.title.downcase, lower_title)
			if best_score.nil? || score > best_score
				best_score = score
				best_match = entry
			end
		end
		if best_score && best_score > 0.8
			return best_match
		else
			return nil
		end
	end

	def slug(text)
		text = text.downcase
		text.gsub!(/^(\d+\.)+ /, '')
		text.gsub!(/[^a-z0-9\-\_]/i, '-')
		text.gsub!('_', '-')
		text.gsub!(/--+/, '-')
		return text
	end
	
	def create_unique_id(title)
		suffix = URANDOM.read(4).unpack('H*')[0].to_i(16).to_s(36)
		return "#{slug(title)}-#{suffix}"
	end

	def open_io(filename_or_io, mode, &block)
		if mode == :read
			if filename_or_io.respond_to?(:readline)
				yield(filename_or_io)
			else
				File.open(filename_or_io, 'r', &block)
			end
		else
			if filename_or_io.respond_to?(:write)
				yield(filename_or_io)
			else
				File.open(filename_or_io, 'w', &block)
			end
		end
	end

	def group_and_sort_entries
		normal = []
		orphaned = []
		
		@entries.each_value do |entry|
			if entry.associated?
				normal << entry
			else
				orphaned << entry
			end
		end
		
		normal.sort!
		orphaned.sort!

		return [normal, orphaned]
	end
end

end