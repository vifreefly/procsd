module Procsd
  class SudoersGenerator < Generator
    def generate_sudoers!(user)
      commands = []
      %w(start stop restart).each { |cmd| commands << "#{systemctl_path} #{cmd} #{target_name}" }
      commands << "#{systemctl_path} reload-or-restart #{app_name}-\\* --all"
      content = "#{user} ALL=NOPASSWD: #{commands.join(', ')}"

      puts "Creating sudoers rule file in the sudoers.d directory (#{SUDOERS_DIR})..."
      temp_path = "/tmp/#{app_name}"

      File.open(temp_path, "w") { |f| f.puts content }
      system "sudo", "chown", "root:root", temp_path
      system "sudo", "chmod", "0440", temp_path
      system "sudo", "mv", temp_path, sudoers_file_path
    end

    def destroy_sudoers!
      if system "sudo", "test", "-e", sudoers_file_path
        system("sudo", "rm", sudoers_file_path) and puts "Sudoers file removed"
      end
    end

    private

    def systemctl_path
      `which systemctl`.strip
    end

    def sudoers_file_path
      "#{SUDOERS_DIR}/#{app_name}"
    end
  end
end
