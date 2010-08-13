require "rubygems"
require "tempfile"
require 'rest_client'
require "rexml/document"

class Scheduler

  def initialize runner
    @runner = runner
  end

  def start
    @runner.start
    while true do
      sleep 1
      @runner.execute
    end
  end

end

class PersonalCodersDojo


  attr_accessor :file, :run_command

  def initialize shell, session_provider
    @filename_formatter = FilenameFormatter.new
    @shell = shell
    @session_provider = session_provider
  end

  def start
    init_session
    execute
  end

  def init_session
    @step = 0
    @session_id = @session_provider.generate_id
    @shell.mkdir_p(@filename_formatter.session_dir @session_id)
  end

  def execute
    change_time = @shell.ctime @file
    if change_time == @previous_change_time then
      return
    end
    result = @shell.execute "#{@run_command} #{@file}"
    state_dir = @filename_formatter.state_dir @session_id, @step
    @shell.mkdir state_dir
    @shell.cp @file, state_dir
    @shell.write_file @filename_formatter.result_file(state_dir), result
    @step += 1
    @previous_change_time = change_time
  end

end

class Shell

  MAX_STDOUT_LENGTH = 100000

  def cp source, destination
    FileUtils.cp source, destination
  end

  def mkdir dir
    FileUtils.mkdir dir
  end

  def mkdir_p dirs
    FileUtils.mkdir_p dirs
  end

  def execute command
    spec_pipe = IO.popen(command, "r")
    result = spec_pipe.read MAX_STDOUT_LENGTH
    spec_pipe.close
    puts result
    result
  end

  def write_file filename, content
    file = File.new filename, "w"
    file << content
    file.close
  end

  def read_file filename
    file = File.new filename
    content = file.read
    file.close
    content
  end

  def ctime filename
    File.new(filename).ctime
  end

end

class SessionIdGenerator

  def generate_id
    Time.new.to_i.to_s
  end

end

class StateReader

  attr_accessor :session_id, :next_step, :source_code_file

  def initialize shell
    @filename_formatter = FilenameFormatter.new
    @shell = shell
    @next_step = 0
  end

  def enough_states?
    dir = Dir.new(@filename_formatter.session_dir @session_id)
    dir.count >= 4
  end

  def get_state_dir
    @filename_formatter.state_dir(@session_id, @next_step)
  end

  def has_next_state
    File.exist?(get_state_dir)
  end

  def read_next_state
    state = State.new
    state_dir = get_state_dir
    state.time = @shell.ctime state_dir
    state.code = @shell.read_file @filename_formatter.source_code_file(state_dir, @source_code_file)
    state.result = @shell.read_file @filename_formatter.result_file(state_dir)
    @next_step += 1
    state
  end

end

class FilenameFormatter

  CODERSDOJO_WORKSPACE = ".codersdojo"
  RESULT_FILE = "result.txt"
  STATE_DIR_PREFIX = "state_"

  def source_code_file state_dir, source_code_file
    state_file state_dir, source_code_file
  end

  def result_file state_dir
    state_file state_dir, RESULT_FILE
  end

  def state_file state_dir, file
    "#{state_dir}/#{file}"
  end

  def state_dir session_id, step
    session_directory = session_dir session_id
    "#{session_directory}/#{STATE_DIR_PREFIX}#{step}"
  end

  def session_dir session_id
    "#{CODERSDOJO_WORKSPACE}/#{session_id}"
  end

end

class Uploader

  def initialize (source_file, session_id, state_reader = StateReader.new(Shell.new))
    @state_reader = state_reader
    @state_reader.source_code_file = source_file
    @state_reader.session_id = session_id
  end

  def upload_kata
    RestClient.post "#{@@hostname}#{@@kata_path}", []
  end

  def upload_states(kata_id)
    while @state_reader.has_next_state
      state = @state_reader.read_next_state
      RestClient.post "#{@@hostname}#{@@kata_path}/#{kata_id}#{@@state_path}", {:code => state.code, :created_at => state.time}
    end
  end

  def upload_kata_and_states
    kata = upload_kata
    upload_states(XMLElementExtractor.extract('kata/id', kata))
    "This is the link to review and comment your kata #{XMLElementExtractor.extract('kata/short-url', kata)}"
  end

  def upload
    return upload_kata_and_states if @state_reader.enough_states?
    return "You need at least two states"
  end

  private
  @@hostname = 'http://www.codersdojo.com'
  #@@hostname = 'http://localhost:3000'
  @@kata_path = '/katas'
  @@state_path = '/states'

end

class XMLElementExtractor
  def self.extract element, xml_string
    doc = REXML::Document.new xml_string
    return doc.elements.each(element) do |found|
      return found.text
    end
  end
end

class State

  attr_accessor :time, :code, :result

  def initialize time=nil, code=nil, result=nil
    @time = time
    @code = code
    @result = result
  end

end

class ArgumentParser
	
	def initialize controller
		@controller = controller
	end
	
	def parse args
		command = args[0] ? args[0] : ""
		if command.downcase == "help" then
			@controller.help
		elsif command.downcase == "upload" then
			@controller.upload args[1..-1]
		elsif command.downcase == "start" then
			@controller.start
		elsif command.downcase == "spec" then
			# for testing purpose: do nothing special
		else
			raise ArgumentError
		end
	end
	
end

class Controller

	def initialize view
		@view = view
	end

	def help
		@view.show_help
	end

	def start
	  file = ARGV[1]
	  @view.show_start_kata file
	  dojo = PersonalCodersDojo.new Shell.new, SessionIdGenerator.new
	  dojo.file = file
	  dojo.run_command = "ruby"
	  scheduler = Scheduler.new dojo
	  scheduler.start
	end

	def upload args
		if args[0] and args[1] then
		  uploader = Uploader.new args[0], args[1]
		  p uploader.upload
		else
			@view.show_missing_upload_arguments_error args[0], args[1]
		end
	end

end


class ConsoleView
	
	def show_help
		puts <<-helptext
		PersonalCodersDojo automatically runs your specs/tests of a code kata.
		Usage: ruby personal_codersdojo.rb command [options]
		Commands:
		 start <kata_file> \t\t Start the spec/test runner.
		 upload <session_directory> \t Upload the kata in <session_directory> to codersdojo.com. <session_directory> is relative to the working directory.
		 help, -h, --help \t\t Print this help text.

		Examples:
		   :/dojo/my_kata$ ruby ../personal_codersdojo.rb start prime.rb
		      Run the tests of prime.rb. The test runs automatically every second if prime.rb was modified.

		   :/dojo/my_kata$ ruby ../personal_codersdojo.rb upload prime.rb /1271665711
		      Upload the kata located in directory ".codersdojo/1271665711" to codersdojo.com.

		helptext
	end
	
	def show_start_kata file
	  puts "Starting PersonalCodersDojo with kata file #{file}. Use Ctrl+C to finish the kata."		
	end
	
	def show_missing_upload_arguments_error arg1, arg2
		puts "Command <upload> recognized but not enough arguments given. Argument 1 was '#{arg1}' and Argument 2 was '#{arg2}'."
	end
	
end

def called_from_spec args
	args[0] == "spec"
end

# entry from shell
if not called_from_spec(ARGV) then
	view = ConsoleView.new
	controller = Controller.new view
	begin
		arg_parser = ArgumentParser.new controller
		command = arg_parser.parse ARGV
	rescue ArgumentError
		controller.help
	end
end
