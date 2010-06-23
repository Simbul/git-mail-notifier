#!/usr/bin/ruby

require 'rubygems'
require 'action_mailer'

class CsvNotifier
  def repo_name
    git_prefix = `git config hooks.emailprefix`.strip
    return git_prefix unless git_prefix.empty?
    dir_name = `pwd`.chomp.split("/").last.gsub(/\.git$/, '')
    return "#{dir_name}"
  end
  
  def main(args)
    if args.empty?
      puts "Configuration file is missing. You need to pass it as an argument."
      return
    end
    
    config_path = Pathname.new(args.first).expand_path
    unless File.exist?(config_path)
      puts "Cannot find configuration file #{config_path}."
      return
    end
    
    @config = YAML::load_file(config_path)
    @mailer = Mailer.new(@config["recipients"], (@config["from"] || "no-reply@nodomain.com"))
    
    begin
      STDIN.each_line do |line|
        oldrev, newrev, ref = line.strip.split
        puts oldrev, newrev, ref
        
        if ref =~ %r"^refs/heads" and newrev != "0000000000000000000000000000000000000000"
          branch = ref.sub('refs/heads/', '')
          mail_body = "
            One or more CSV files have been updated in the #{repo_name} repository (#{branch} branch).
            They are attached to this mail as a compressed ZIP archive.

            "

          if oldrev == "0000000000000000000000000000000000000000"
            # No old revision specified: it has to be a new branch
            oldrev = `git rev-list --reverse #{newrev} | head -1`.strip
            mail_body = "
              A new branch named #{branch} has been created on repository #{repo_name}.
              The CSV files contained in the branch are attached to this mail as a compressed ZIP archive.

              "
          end

          files = `git diff --diff-filter=ACM --name-only #{oldrev} #{newrev}`.strip

          csvs = []
          files.each do |filename|
            if filename =~ %r/csv$/
              csvs << filename.strip
            end
          end
          unless csvs.empty?
            archive = `git archive --format=zip #{newrev} #{csvs.join(" ")}`
            @mailer.deliver_zip_message(archive, mail_body, "csv_#{repo_name}_#{branch}_#{Time.now.strftime("%Y-%m-%d_%H-%M")}.zip")
            puts "Sent CSV notification email"
          end
        end
      end
    rescue Exception => e
      puts "Exception in CSV mailer hook: #{e}"
      puts "Hook params: #{oldrev} #{newrev} #{ref}"
    end
  end
  
end

class Mailer < ActionMailer::Base
  def initialize(recipients, from)
    @recipients = recipients
    @from = from
  end
  
  def zip_message(attachment_body, message_body, filename)
    recipients @recipients
    from       @from
    subject    "New CSV for #{repo_name}"
    body       message_body

    attachment :content_type => "application/zip",
      :body => attachment_body,
      :filename => filename
  end
end

if __FILE__ == $0
  n = CsvNotifier.new
  n.main(ARGV)
end
