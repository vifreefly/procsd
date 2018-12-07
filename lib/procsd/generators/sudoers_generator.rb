module Procsd
  class SudoersGenerator < Generator
    def generate_sudoers!(user)
      systemctl_path = `which systemctl`.strip
      commands = []
      %w(start stop restart).each { |cmd| commands << "#{systemctl_path} #{cmd} #{target_name}" }
      commands << "#{systemctl_path} reload-or-restart #{app_name}-\\* --all"
      content = "#{user} ALL=NOPASSWD: #{commands.join(', ')}"

      puts "Creating sudoers rule file in the sudoers.d directory (#{SUDOERS_DIR})..."
      temp_path = "/tmp/#{app_name}"
      dest_path = "#{SUDOERS_DIR}/#{app_name}"

      File.open(temp_path, "w") { |f| f.puts content }
      system "sudo", "chown", "root:root", temp_path
      system "sudo", "chmod", "0440", temp_path
      system "sudo", "mv", temp_path, dest_path
    end
  end
end
