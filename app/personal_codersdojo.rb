require "tempfile"

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
		if change_time == @previous_change_time then return end
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

class StateUploader
	
	API_PREFIX = "restapi"
	
	def initialize server_url, api
		@url_prefix = "#{server_url}/#{API_PREFIX}"
		@api = api
	end
	
	def init_upload
		@uuid = @api.get "#{@url_prefix}/uuid"
	end
	
	def upload_state state
		@api.post "#{@url_prefix}/state", {:uuid => @uuid, :time => state.time, :code => state.code, :result => state.result}
	end
	
end

class StateReader
	
	attr_accessor :session_id, :next_step, :source_code_file
	
	def initialize shell
		@filename_formatter = FilenameFormatter.new
		@shell = shell
		@next_step = 0
	end
	
	def read_next_state
		state = State.new
		state_dir = @filename_formatter.state_dir(@session_id, @next_step)
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

class State
	
	attr_accessor :time, :code, :result
	
	def initialize time=nil, code=nil, result=nil
		@time = time
		@code = code
		@result = result
	end
	
end

def run_from_shell
	file = ARGV[1]
	puts "Starting PersonalCodersDojo with kata file #{file}. Use Ctrl+C to finish the kata."
	dojo = PersonalCodersDojo.new Shell.new, SessionIdGenerator.new
	dojo.file = file
	dojo.run_command = "ruby"
	scheduler = Scheduler.new dojo
	scheduler.start
end

def print_help
	puts <<-helptext
PersonalCodersDojo automatically runs your specs/tests of a code kata.
Usage: ruby personal_codersdojo.rb command
Commands:
 start <kata_file> \t\t Start the spec/test runner.
 upload <session_directory> \t Upload the kata to codersdojo.com.
 help, -h, --help \t\t Print this help text.

Examples:
 ruby personal_codersdojo.rb run prime.rb
   Run the tests of prime.rb. The test runs automatically every second if prime.rb was modified.
 ruby personal_codersdojo.rb upload .codersdojo/1271665711
   Upload the kata located in directory ".codersdojo/1271665711" to codersdojo.com.

helptext
end

if ARGV[0] == "start" then
	run_from_shell
elsif ARGV[0] == "spec" then
	
else
	print_help
end

