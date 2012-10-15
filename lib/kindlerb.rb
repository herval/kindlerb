# encoding: utf-8

unless `which kindlegen` =~ /kindlegen/
  abort "Please install kindlegen on your path"
end

# extract nav structure

require 'pathname'
require 'yaml'
require 'nokogiri'
require 'mustache'
require 'fileutils'

# monkeypatch
class String
  def shorten(max)
    length > max ? Array(self[0,max].split(/\s+/)[0..-2]).join(' ') + '...' : self
  end
end


module Kindlerb
  VERSION = '0.0.10'

  # allows overriding the default mustaches with ones specified under the templates folder
  def self.custom_or_default_template(target_dir, name)
    custom = File.join(target_dir, "templates", "#{name}.mustache")
    if File.exist?(custom)
      puts "Using custom template for #{name}.mustache"
      File.read(custom)
    else
      File.read(File.join(File.dirname(__FILE__), '..', "templates", "#{name}.mustache"))
    end
  end

  def self.prepare_content(target_dir)
    opf_template = custom_or_default_template(target_dir, "opf")
    ncx_template = custom_or_default_template(target_dir, "ncx")
    contents_template = custom_or_default_template(target_dir, "contents")
    section_template = custom_or_default_template(target_dir, "section")
    # masthead_gif = File.join(File.dirname(__FILE__), '..', "templates/masthead.gif")
    # cover_gif = File.join(File.dirname(__FILE__), '..', "templates/cover-image.gif")

    Dir.chdir target_dir do
      playorder = 1

      images = []
      manifest_items = []

      unless File.exist?("_document.yml")
        
        puts "Usage: kindlerb [target file directory]"

        abort "Missing _document.yml. Your input file tree is not structured correctly. Please read the README."
      end

      document = YAML::load_file("_document.yml")

      document[:spine_items] = []
      section_html_files = []

      sections = Dir['sections/*'].entries.sort.map.with_index {|section_dir| 
        c = File.read(Pathname.new(section_dir) + '_section.txt')
        c.force_encoding("UTF-8")
        section_title = c.strip
        articles = Dir[Pathname.new(section_dir) + '*'].entries.select {|x| File.basename(x) !~ /section/}.sort
        section_html_files << (section_html_file = (Pathname.new(section_dir) + 'section.html').to_s)
        idref = "item-#{section_dir.gsub(/\D/, '')}"

        document[:spine_items] << {:idref => idref}
        manifest_items << {
          :href => section_html_file,
          :media => "application/xhtml+xml",
          :idref => idref
        }

        s = {
          :path => section_dir,
          :title => section_title.shorten(40),
          :playorder => (playorder += 1),
          :idref => idref,
          :href => Pathname.new(section_dir) + 'section.html',
          :articles => articles.map {|article_file|
                doc = Nokogiri::HTML(File.read(article_file))
                article_images = doc.search("img").map {|img| 
                  mimetype =  img[:src] ? "image/#{File.extname(img[:src]).sub('.', '')}" : nil
                  {:href => img[:src], :mimetype => mimetype}
                }
                images.push *article_images
                title = doc.search("html/head/title").map(&:inner_text).first || "no title"
                idref = "item-#{article_file.gsub(/\D/, '')}"
                document[:spine_items] << {:idref => idref}
                article = {
                  :file => article_file,
                  :href => article_file,
                  :title => title, 
                  :short_title => title.shorten(60),
                  :author => doc.search("html/head/meta[@name=author]").map{|n|n[:content]}.first,
                  :description => doc.search("html/head/meta[@name=description]").map{|n|n[:content]}.first,
                  :playorder => (playorder += 1),
                  :idref => idref
                }
                manifest_items << {
                  :href => article[:file],
                  :media => "application/xhtml+xml",
                  :idref => article[:idref]
                }
                article
            }
        }

        # Generate the section html
        out = Mustache.render section_template, s
        File.open(section_html_file, "w") {|f| f.puts out}
        s

      }

      document[:first_article] = sections[0][:articles][0]
      document['sections'] = sections


      document[:manifest_items] = manifest_items + images.map.with_index {|img, idx| 
        {
          :href => img[:href],
          :media => img[:mimetype],
          :idref => "img-%03d" % idx
        }
      } 
     
      opf = Mustache.render opf_template, document
      File.open("kindlerb.opf", "w") {|f| f.puts opf}
      puts "Wrote #{target_dir}/kindlerb.opf"

      # NCX
      ncx = Mustache.render ncx_template, document
      File.open("nav-contents.ncx", "w") {|f| f.puts ncx}
      puts "Wrote #{target_dir}/nav-contents.ncx"

      # contents
      contents = Mustache.render contents_template, document
      File.open("contents.html", "w") {|f| f.puts contents}
      puts "Wrote #{target_dir}/contents.html"  
    end
  end

  def self.generate_mobi(target_dir)
    Dir.chdir target_dir do
      document = YAML::load_file("_document.yml")

      outfile = document['mobi_outfile']
      puts "Writing #{outfile}"
      cmd = "kindlegen -verbose -c2 -o #{outfile} kindlerb.opf && echo 'Wrote MOBI to #{outfile}'"
      puts cmd
      system cmd
    end
  end

  def self.run
    target_dir = Pathname.new(ARGV.first || '.')

    self.prepare_content(target_dir)
    self.generate_mobi(target_dir)
  end
end
