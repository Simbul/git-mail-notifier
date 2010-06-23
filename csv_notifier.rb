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
  
  def expand_placeholders(text)
    text.gsub("REPO_NAME", repo_name).gsub("BRANCH_NAME", @branch_name)
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
    @to = @config["recipients"]
    @from = @config["from"] || "no-reply@nodomain.com"
    @branch_name = ""
    
    STDIN.each_line do |line|
      oldrev, newrev, ref = line.strip.split
      
      begin
        if ref =~ %r"^refs/heads" and newrev != "0000000000000000000000000000000000000000"
          @branch_name = ref.sub('refs/heads/', '')
          mail_body = expand_placeholders(@config["body"])
          mail_subject = expand_placeholders(@config["subject"])

          if oldrev == "0000000000000000000000000000000000000000"
            # No old revision specified: it has to be a new branch
            oldrev = `git rev-list --reverse #{newrev} | head -1`.strip
            mail_body = expand_placeholders(@config["body_new_branch"])
            mail_subject = expand_placeholders(@config["subject_new_branch"])
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
            Mailer.deliver_zip_message(
              @to,
              @from,
              mail_subject,
              archive,
              mail_body,
              "csv_#{repo_name}_#{@branch_name}_#{Time.now.strftime("%Y-%m-%d_%H-%M")}.zip"
            )
            puts "Sent CSV notification email"
          end
        end
      rescue Exception => e
        puts "Exception in CSV notifier hook: #{e}"
        puts "Hook params: #{oldrev} #{newrev} #{ref}"
      end
    end
  end
  
end

class Mailer < ActionMailer::Base
  def zip_message(to_field, from_field, subject_field, attachment_body, message_body, filename)
    recipients to_field
    from       from_field
    subject    subject_field
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
