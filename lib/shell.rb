class Shell
  def initialize(working_directory)
    @working_directory = working_directory
  end

  def run(*command)
    system(*command, chdir: @working_directory, exception: true)
  end

  def read(*command)
    invocation = (command.length == 1) ? command.first : command
    output = IO.popen(invocation, chdir: @working_directory, &:read)
    status = $?
    raise "Command failed (#{status}): #{command.join(' ')}" unless status.success?

    output
  end
end
