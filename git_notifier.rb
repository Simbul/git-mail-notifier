#!/usr/bin/ruby

require 'rubygems'
require 'action_mailer'

class GitNotifier
  # Return the name of the current Git repository.
  def repo_name
    git_prefix = `git config hooks.emailprefix`.strip
    return git_prefix unless git_prefix.empty?
    dir_name = `pwd`.chomp.split("/").last.gsub(/\.git$/, '')
    return "#{dir_name}"
  end
  
  # Return the provided string with placeholders substituted with actual values.
  def expand_placeholders(text)
    text \
      .gsub("REPO_NAME", repo_name) \
      .gsub("BRANCH_NAME", @branch_name) \
      .gsub("FILE_NAMES", @file_names) \
      .gsub("FILE_DIFFS", @file_diffs)
  end
  
  # Run the script.
  # The script has a single required parameter: a YAML configuration file.
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
    
    if @config["exclude_branches"]
      @exclude_branches = @config["exclude_branches"].split
    else
      @exclude_branches = []
    end
    if @config["include_branches"]
      @include_branches = @config["include_branches"].split
    else
      @include_branches = []
    end
    if @config["include_matches"] and !@config["include_matches"].empty?
      @include_matches = Regexp.new(@config["include_matches"])
    else
      @include_matches = Regexp.new(".*")
    end
    
    STDIN.each_line do |line|
      oldrev, newrev, ref = line.strip.split
      @branch_name = ""
      @file_diffs = ""
      
      begin
        if ref =~ %r"^refs/heads" and newrev != "0000000000000000000000000000000000000000"
          @branch_name = ref.sub('refs/heads/', '')
          
          next if @exclude_branches.include? @branch_name
          next if !@include_branches.empty? and !@include_branches.include? @branch_name
          
          tmp_body = @config["body"]
          tmp_subject = @config["subject"]

          if oldrev == "0000000000000000000000000000000000000000"
            # No old revision specified: it has to be a new branch
            oldrev = `git rev-list --reverse #{newrev} | head -1`.strip
            tmp_body = @config["body_new_branch"]
            tmp_subject = @config["subject_new_branch"]
          end

          files = `git diff --diff-filter=ACMDR --name-status #{oldrev} #{newrev}`.strip

          matching_files = []
          matching_lines = []
          files.each do |file_line|
            status, name = file_line.split("\t")
            if name =~ @include_matches
              matching_files << name.strip
              matching_lines << file_line.strip
            end
          end
          
          @file_names = matching_lines.join("\n")
          
          unless matching_files.empty?
            @file_diffs = `git diff #{oldrev} #{newrev} -- #{matching_files.join(" ")}`
            
            archive = `git archive --format=zip #{newrev} #{matching_files.join(" ")}`
            Mailer.deliver_zip_message(
              @to,
              @from,
              expand_placeholders(tmp_subject),
              archive,
              expand_placeholders(tmp_body),
              "file_#{repo_name}_#{@branch_name}_#{Time.now.strftime("%Y-%m-%d_%H-%M")}.zip"
            )
            puts "Sent notification email"
          end
        end
      rescue Exception => e
        puts "Exception in notifier hook: #{e}"
        puts "Hook params: #{oldrev} #{newrev} #{ref}"
      end
    end
  end
  
end

class Mailer < ActionMailer::Base
  # Send a mail with an attached zip file.
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
  n = GitNotifier.new
  n.main(ARGV)
end
