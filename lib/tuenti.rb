require 'active_support'
require 'mechanize'
require 'json'
DEBUG = false unless defined? DEBUG

class Tuenti
  extend ActiveSupport::Memoizable

  LOGIN_URL = 'https://www.tuenti.com/?m=Login&func=do_login'
  HOME_URL = 'http://www.tuenti.com/?m=home&func=view_home'
  UPLOAD_URL = 'http://fotos.tuenti.com/?upload=1&iframe=1'
  ALBUMS_URL = 'http://www.tuenti.com/?m=Search&func=get_user_custom_albums_for_data_source&ajax=1'
  EDIT_PHOTO_URL = 'http://www.tuenti.com/?m=Photoedit&func=process_edit_photo&ajax=1'

  CSFR_REGEXP = /csfr(&quot;)?[:=](&quot;)?([0-9a-zA-Z]+)\b/
  CSFR_REGEXP_INDEX = 3

  def initialize(user, password, timezone = Time.now.utc_offset/3600)
    @agent = WWW::Mechanize.new
    raise Exception if @agent.post(LOGIN_URL, :email => user, :input_password => password, :timezone => timezone).uri.to_s == LOGIN_URL
    @csfr = @agent.get(HOME_URL).body.match(CSFR_REGEXP)[CSFR_REGEXP_INDEX]
  end

  def upload_photo(file, attributes = nil)
    qid = @agent.submit(upload_photo_form(file)).search('#request_data').text
    puts "QID: #{qid}" if DEBUG
    id = nil
    # el formato del id es album_id-user_id-photo_id-user_id
    while id.nil? || id =~ /-0-/ do # hasta que no se procesa photo_id es 0
      sleep(0.5)
      id = @agent.post(UPLOAD_URL, :func => 'checkq', :qid => qid).search('#request_data').text
    end
    puts "PHOTO ID: #{id}" if DEBUG
    if attributes
      options = {:csfr => @csfr, :'item_ids[]' => id, :from_collection_key => id, :photo_title => attributes[:title] || ''}
      if attributes[:album]
        options[:'add_albums_collection_keys[]'] = album_id(attributes[:album])
        #@new_albums_count = 0
        puts options[:'add_albums_collection_keys[]'] if DEBUG
      end
      @agent.post EDIT_PHOTO_URL + "&collection_key=#{id}", options
    end
    id
  end


  def albums
    JSON.parse(@agent.get(ALBUMS_URL).search('#request_data').text)["results"].inject({}) do |albums, result|
      albums.update(result["string"] => result["id"])
    end
  end
  memoize :albums

  def album_id(album)
    albums[album] || new_album_id(album) 
  end

  def set_album(*photos)
  end

  private
  def new_album_id(album)
    flush_cache :albums
    @new_albums_count ||= 0
    "__NEW_ALBUM__#{album}__NEW_ALBUM_END__#{@new_albums_count+=1}"
  end

  def upload_photo_form(file)
    form = build_form(UPLOAD_URL, 'POST', true)
    form.file_uploads << WWW::Mechanize::Form::FileUpload.new("name", file)
    form.fields << WWW::Mechanize::Form::Field.new("func",'addq')
    form.fields << WWW::Mechanize::Form::Field.new("rotate",'0')
    form
  end

  def build_form(action, method = 'POST', multipart = false)
    node = Nokogiri::XML::Element.new('form', Nokogiri::XML::Document.new) do |form|
      form['action'] = action
      form['method'] = method
      form['enctype'] = 'multipart/form-data' if multipart
    end
    form = WWW::Mechanize::Form.new(node)
  end
end
