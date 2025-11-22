require 'feedjira'
require 'httparty'
require 'jekyll'
require 'nokogiri'
require 'time'

module ExternalPosts
  class ExternalPostsGenerator < Jekyll::Generator
    safe true
    priority :high

    DEFAULT_REQUEST_OPTIONS = {
      headers: {
        'User-Agent' => 'ExternalPostsFetcher/1.0'
      },
      timeout: 10
    }.freeze

    def generate(site)
      if site.config['external_sources'] != nil
        site.config['external_sources'].each do |src|
          puts "Fetching external posts from #{src['name']}:"
          if src['rss_url']
            fetch_from_rss(site, src)
          elsif src['posts']
            fetch_from_urls(site, src)
          end
        end
      end
    end

    def fetch_from_rss(site, src)
      response = HTTParty.get(src['rss_url'], DEFAULT_REQUEST_OPTIONS)

      unless response_ok?(response)
        log_warning(site, src, "Request failed with status #{response.code}")
        return
      end

      xml = response.body
      if xml.nil? || xml.strip.empty?
        log_warning(site, src, 'Feed response was empty')
        return
      end

      begin
        feed = Feedjira.parse(xml)
      rescue Feedjira::NoParserAvailable => e
        log_warning(site, src, "Feedjira could not parse the feed: #{e.message}")
        return
      rescue StandardError => e
        log_warning(site, src, "Unexpected error parsing feed: #{e.class} - #{e.message}")
        return
      end

      process_entries(site, src, feed.entries)
    rescue StandardError => e
      log_warning(site, src, "Failed to fetch RSS feed: #{e.class} - #{e.message}")
    end

    def process_entries(site, src, entries)
      entries.each do |e|
        puts "...fetching #{e.url}"
        create_document(site, src['name'], e.url, {
          title: e.title,
          content: e.content,
          summary: e.summary,
          published: e.published
        })
      end
    end

    def create_document(site, source_name, url, content)
      # check if title is composed only of whitespace or foreign characters
      if content[:title].gsub(/[^\w]/, '').strip.empty?
        # use the source name and last url segment as fallback
        slug = "#{source_name.downcase.strip.gsub(' ', '-').gsub(/[^\w-]/, '')}-#{url.split('/').last}"
      else
        # parse title from the post or use the source name and last url segment as fallback
        slug = content[:title].downcase.strip.gsub(' ', '-').gsub(/[^\w-]/, '')
        slug = "#{source_name.downcase.strip.gsub(' ', '-').gsub(/[^\w-]/, '')}-#{url.split('/').last}" if slug.empty?
      end

      path = site.in_source_dir("_posts/#{slug}.md")
      doc = Jekyll::Document.new(
        path, { :site => site, :collection => site.collections['posts'] }
      )
      doc.data['external_source'] = source_name
      doc.data['title'] = content[:title]
      doc.data['feed_content'] = content[:content]
      doc.data['description'] = content[:summary]
      doc.data['date'] = content[:published]
      doc.data['redirect'] = url
      site.collections['posts'].docs << doc
    end

    def fetch_from_urls(site, src)
      src['posts'].each do |post|
        puts "...fetching #{post['url']}"
        content = fetch_content_from_url(post['url'])
        next if content.nil?

        content[:published] = parse_published_date(post['published_date'])
        create_document(site, src['name'], post['url'], content)
      rescue StandardError => e
        log_warning(site, src, "Failed to fetch #{post['url']}: #{e.class} - #{e.message}")
      end
    end

    def parse_published_date(published_date)
      case published_date
      when String
        Time.parse(published_date).utc
      when Date
        published_date.to_time.utc
      else
        raise "Invalid date format for #{published_date}"
      end
    end

    def fetch_content_from_url(url)
      response = HTTParty.get(url, DEFAULT_REQUEST_OPTIONS)

      return nil unless response_ok?(response)

      html = response.body
      parsed_html = Nokogiri::HTML(html)

      title = parsed_html.at('head title')&.text.strip || ''
      description = parsed_html.at('head meta[name="description"]')&.attr('content') || ''
      body_content = parsed_html.at('body')&.inner_html || ''

      {
        title: title,
        content: body_content,
        summary: description
        # Note: The published date is now added in the fetch_from_urls method.
      }
    end

    private

    def response_ok?(response)
      response.respond_to?(:success?) && response.success?
    end

    def log_warning(site, src, message)
      Jekyll.logger.warn('ExternalPosts', "#{src['name']}: #{message}")
    end

  end
end
