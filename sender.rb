require 'rest-client'
require 'json'
require 'date'
require 'csv'
require 'yaml'

$stdout.reopen("out.txt", "w")
$stderr.reopen("err.txt", "w")

CONFIG = YAML.load_file('./secrets/secrets.yml')

date = Date.today-1

file_date = date.strftime("%Y%m")
csv_file_name = "reviews_#{CONFIG["package_name"]}_#{file_date}.csv"

o = `BOTO_PATH=./secrets/.boto && ./gsutil/gsutil cp -r gs://#{CONFIG["app_repo"]}/reviews/#{csv_file_name} .`
p o

class Slack
  def self.notify(message)
    payload1 = {}
  payload1["text"] = 'You have ' + message.length.to_s + ' new Android reviews'
  payload1["username"] = "AndroidBot"
  payload1["icon_url"] = "http://www.android.com/media/android_vector.jpg"

  payload1["attachments"] = message
  RestClient.post CONFIG["slack_url"], {
      payload: payload1.to_json
    },
    content_type: :json,
    accept: :json
  end
  
  def self.sendPayload(payload)
  RestClient.post CONFIG["slack_url"], 
  payload,
  content_type: :json,
  accept: :json
  sleep 1
  end
end

class Review
  def self.collection
    @collection ||= []
  end

  def self.send_reviews_from_date(date)
    attachments = collection.select do |r|
      r.submitted_at > date && (r.title || r.text)
    end.sort_by do |r|
      r.submitted_at
    end.map do |r|
    r.build_attachment
  end

  if attachments.empty?
      print "No new reviews\n"
    else
      Slack.notify(attachments)
    end
  end

  attr_accessor :text, :title, :submitted_at, :original_subitted_at, :rate, :device, :url, :version, :edited, :version_name

  def initialize data = {}
    @text = data[:text] ? data[:text].to_s.encode("utf-8") : nil
    @title = data[:title] ? "*#{data[:title].to_s.encode("utf-8")}" : nil

    @submitted_at = DateTime.parse(data[:submitted_at].encode("utf-8"))
    @original_subitted_at = DateTime.parse(data[:original_subitted_at].encode("utf-8"))

    @rate = data[:rate].encode("utf-8").to_i
    @device = data[:device] ? data[:device].to_s.encode("utf-8") : nil
    @url = data[:url].to_s.encode("utf-8")
    @version = data[:version].to_s.encode("utf-8")
    @version_name = data[:version_name].to_s.encode("utf-8")
    @edited = data[:edited]
  end

  def notify_to_slack
    if text || title
      message = "*Rating: #{rate}* | version: #{version_name} | posted: #{submitted_at}\n #{[title, text].join(" ")}\n <#{url}|Google play>"
      Slack.notify(message)
    end
  end

  def build_message
    date = if edited
             "posted: #{original_subitted_at.strftime("%m.%d.%Y at %I:%M%p")}, edited: #{submitted_at.strftime("%m.%d.%Y at %I:%M%p")}"
           else
             "posted: #{submitted_at.strftime("%m.%d.%Y at %I:%M%p")}"
           end

    stars = rate.times.map{"*"}.join + (5 - rate).times.map{"-"}.join

    [
      "\n\n#{stars}",
      "Version: #{version_name} | #{date}",
      "#{[title, text].join(" ")}",
      "<#{url}|Google play>"
    ].join("\n")
  end
  
  def build_attachment
  color = if self.rate > 3
        "good"
      elsif self.rate == 3
        "warning"
      else
        "danger"
      end
  date = if edited
             "posted: #{original_subitted_at.strftime("%m.%d.%Y at %I:%M%p")}, edited: #{submitted_at.strftime("%m.%d.%Y at %I:%M%p")}"
           else
             "posted: #{submitted_at.strftime("%m.%d.%Y at %I:%M%p")}"
           end

    stars = rate.times.map{"*"}.join + (5 - rate).times.map{"-"}.join
    attText = [
      "\n\n#{stars}",
      "Version: #{version_name} | #{date}",
      "#{text}"
    ].join("\n")
  attachment = {}
  attachment['fallback'] = if self.title.nil?
                "Android review"
              else 
                self.title
              end
  attachment['title'] = self.title
  attachment['color'] = color
  attachment['text'] = attText
  attachment["unfurl_links"] = true
  attachment["unfurl_media"] = true
  return attachment
  end
end

CSV.foreach(csv_file_name, encoding: 'bom|utf-16le', headers: true) do |row|
  # If there is no reply - push this review
  if row[12].nil?
    Review.collection << Review.new({
      text: row[11],
      title: row[10],
      submitted_at: row[7],
      edited: (row[5] != row[7]),
      original_subitted_at: row[5],
      rate: row[9],
      device: row[4],
      url: row[15],
      version: row[1],
      version_name: row[2]
    })
  end
end

Review.send_reviews_from_date(date)
print "Script ran #{Date.today}\n"
