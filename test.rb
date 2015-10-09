#require 'rest-client'
require 'json'
require 'date'
require 'csv'
require 'yaml'

CONFIG = YAML.load_file('./secrets/secrets.yml')

date = Date.today-5

file_date = date.strftime("%Y%m")
csv_file_name = "reviews_#{CONFIG["package_name"]}_#{file_date}.csv"

class Slack
  def self.notify(message)
    RestClient.post CONFIG["slack_url"], {
      payload:
      { text: message }.to_json
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
    collection.select do |r|
      r.submitted_at > date && (r.title || r.text)
    end.sort_by do |r|
      r.submitted_at
    end.each {|r| Slack.sendPayload(r.build_payload)}

=begin
    if message != ""
      Slack.notify(message)
    else
      print "No new reviews\n"
    end
=end
  end
  
  def self.send_single_reviews_from_date(date)
	message = collection.select do |r|
      r.submitted_at > date && (r.title || r.text)
    end.sort_by do |r|
      r.submitted_at
    end.map do |r|
      r.build_message
    end.join("\n")


    if message != ""
      Slack.notify(message)
    else
      print "No new reviews\n"
    end
  end

  attr_accessor :text, :title, :submitted_at, :original_subitted_at, :rate, :device, :url, :version, :edited

  def initialize data = {}
    @text = data[:text] ? data[:text].to_s.encode("utf-8") : nil
    @title = data[:title] ? "*#{data[:title].to_s.encode("utf-8")}*\n" : nil

    @submitted_at = DateTime.parse(data[:submitted_at].encode("utf-8"))
    @original_subitted_at = DateTime.parse(data[:original_subitted_at].encode("utf-8"))

    @rate = data[:rate].encode("utf-8").to_i
    @device = data[:device] ? data[:device].to_s.encode("utf-8") : nil
    @url = data[:url].to_s.encode("utf-8")
    @version = data[:version].to_s.encode("utf-8")
    @edited = data[:edited]
  end

  def notify_to_slack
    if text || title
      message = "*Rating: #{rate}* | version: #{version} | posted: #{submitted_at}\n #{[title, text].join(" ")}\n <#{url}|Google play>"
      Slack.notify(message)
    end
  end

  def build_message
    date = if edited
             "posted: #{original_subitted_at.strftime("%m.%d.%Y at %I:%M%p")}, edited: #{submitted_at.strftime("%m.%d.%Y at %I:%M%p")}"
           else
             "posted: #{submitted_at.strftime("%m.%d.%Y at %I:%M%p")}"
           end

    stars = rate.times.map{"★"}.join + (5 - rate).times.map{"☆"}.join

    [
      "\n\n#{stars}",
      "Version: #{version} | #{date}",
      "#{[title, text].join(" ")}",
      "<#{url}|Google play>"
    ].join("\n")
  end
  
  def build_payload
	color = if self.rate > 3
				"good"
			elsif self.rate = 3
				"warning"
			else
				"danger"
			end
	date = if edited
             "posted: #{original_subitted_at.strftime("%m.%d.%Y at %I:%M%p")}, edited: #{submitted_at.strftime("%m.%d.%Y at %I:%M%p")}"
           else
             "posted: #{submitted_at.strftime("%m.%d.%Y at %I:%M%p")}"
           end

    stars = rate.times.map{"★"}.join + (5 - rate).times.map{"☆"}.join

    text = [
      "\n\n#{stars}",
      "Version: #{version} | #{date}",
      "#{[title, text].join(" ")}",
      "<#{url}|Google play>"
    ].join("\n")
	attachment = {}
	attachment['title'] = self.title
	attachment['color'] = color
	attachment['text'] = text
	attachments = [attachment]
	payload = {}
	payload['attachments'] = attachments
	print payload.to_json
  end
end

CSV.foreach(csv_file_name, encoding: 'bom|utf-16le', headers: true) do |row|
  # If there is no reply - push this review
  if row[11].nil?
    Review.collection << Review.new({
      text: row[10],
      title: row[9],
      submitted_at: row[6],
      edited: (row[4] != row[6]),
      original_subitted_at: row[4],
      rate: row[8],
      device: row[3],
      url: row[14],
      version: row[1],
    })
  end
end

Review.send_reviews_from_date(date)
