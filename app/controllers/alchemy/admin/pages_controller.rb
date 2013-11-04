module Alchemy
  module Admin
    class PagesController < Alchemy::Admin::BaseController
      helper 'alchemy/pages'

      before_filter :set_translation,
        except: [:show]

      before_filter :load_page,
        only: [:show, :info, :unlock, :visit, :publish, :configure, :edit, :update, :destroy, :fold]

      authorize_resource class: Alchemy::Page

      def index
        @page_root = Page.language_root_for(session[:language_id])
        @locked_pages = Page.from_current_site.all_locked_by(current_alchemy_user)
        @languages = Language.all
        if !@page_root
          if @languages.length == 1
            @language = @languages.first
            store_language_in_session(@language)
          else
            @language = @languages.find { |language| language.id == session[:language_id] }
          end
          @languages_with_page_tree = Language.all_for_created_language_trees if @language
        end
      end

      # Used by page preview iframe in Page#edit view.
      #
      def show
        @preview_mode = true
        @root_page = Page.language_root_for(session[:language_id])
        # Setting the locale to pages language. so the page content has its correct translation
        ::I18n.locale = @page.language_code
        render :layout => layout_for_page
      rescue Exception => e
        exception_logger(e)
        render :file => Rails.root.join('public', '500.html'), :status => 500, :layout => false
      end

      def info
        render layout: !request.xhr?
      end

      def new
        @page = Page.new(:layoutpage => params[:layoutpage] == 'true', :parent_id => params[:parent_id])
        @page_layouts = PageLayout.layouts_for_select(session[:language_id], @page.layoutpage?)
        @clipboard_items = Page.all_from_clipboard_for_select(get_clipboard[:pages], session[:language_id], @page.layoutpage?)
      end

      def create
        if params[:paste_from_clipboard]
          source = Page.find(params[:paste_from_clipboard])
          parent = Page.find_by_id(params[:page][:parent_id]) || Page.root
          @page = Page.paste_from_clipboard(source, parent, params[:page][:name])
        else
          @page = Page.new(page_params)
        end
        if @page.save
          flash[:notice] = _t("Page created", :name => @page.name)
          do_redirect_to(redirect_path_after_create_page)
        else
          @page_layouts = PageLayout.layouts_for_select(session[:language_id], @page.layoutpage?)
          @clipboard_items = Page.all_from_clipboard_for_select(get_clipboard[:pages], session[:language_id], @page.layoutpage?)
          render :new
        end
      end

      # Edit the content of the page and all its elements and contents.
      def edit
        # fetching page via before filter
        if page_is_locked?
          flash[:notice] = _t("This page is locked by %{name}", name: @page.locker_name)
          redirect_to admin_pages_path
        else
          @page.lock_to!(current_alchemy_user)
          @locked_pages = Page.from_current_site.all_locked_by(current_alchemy_user)
        end
        @layoutpage = @page.layoutpage?
      end

      # Set page configuration like page names, meta tags and states.
      def configure
        @page_layouts = PageLayout.layouts_with_own_for_select(@page.page_layout, session[:language_id], @page.layoutpage?)
        render @page.redirects_to_external? ? 'configure_external' : 'configure'
      end

      # Updates page
      #
      # * fetches page via before filter
      #
      def update
        # stores old page_layout value, because unfurtunally rails @page.changes does not work here.
        @old_page_layout = @page.page_layout
        if @page.update_attributes(page_params)
          @notice = _t("Page saved", :name => @page.name)
          @while_page_edit = request.referer.include?('edit')
        else
          configure
        end
      end

      def destroy
        # fetching page via before filter
        name = @page.name
        @page_id = @page.id
        @layoutpage = @page.layoutpage?
        if @page.destroy
          @page_root = Page.language_root_for(session[:language_id])
          @message = _t("Page deleted", :name => name)
          flash[:notice] = @message
          respond_to do |format|
            format.js
          end
          # remove from clipboard
          get_clipboard.remove(:pages, @page_id)
        end
      end

      def link
        @url_prefix = ""
        if configuration(:show_real_root)
          @page_root = Page.root
        else
          @page_root = Page.language_root_for(session[:language_id])
        end
        @area_name = params[:area_name]
        @content_id = params[:content_id]
        @attachments = Attachment.all.collect { |f| [f.name, download_attachment_path(:id => f.id, :name => f.urlname)] }
        if params[:link_urls_for] == "newsletter"
          @url_prefix = current_server
        end
        if multi_language?
          @url_prefix = "#{session[:language_code]}/"
        end
      end

      def fold
        # @page is fetched via before filter
        @page.fold!(current_alchemy_user.id, !@page.folded?(current_alchemy_user.id))
        respond_to do |format|
          format.js
        end
      end

      # Leaves the page editing mode and unlocks the page for other users
      def unlock
        # fetching page via before filter
        @page.unlock!
        flash[:notice] = _t(:unlocked_page, :name => @page.name)
        @pages_locked_by_user = Page.from_current_site.all_locked_by(current_alchemy_user)
        respond_to do |format|
          format.js
          format.html {
            redirect_to params[:redirect_to].blank? ? admin_pages_path : params[:redirect_to]
          }
        end
      end

      def visit
        @page.unlock!
        redirect_to show_page_path(:urlname => @page.urlname, :lang => multi_language? ? @page.language_code : nil)
      end

      # Sets the page public
      def publish
        # fetching page via before filter
        @page.publish!
        flash[:notice] = _t(:page_published, :name => @page.name)
        redirect_back_or_to_default(admin_pages_path)
      end

      def copy_language_tree
        # copy language root from old to new language
        if params[:layoutpage]
          original_language_root = Page.layout_root_for(params[:languages][:old_lang_id])
        else
          original_language_root = Page.language_root_for(params[:languages][:old_lang_id])
        end
        new_language_root = Page.copy(
          original_language_root,
          :language_id => params[:languages][:new_lang_id],
          :language_code => session[:language_code]
        )
        new_language_root.move_to_child_of Page.root
        original_language_root.copy_children_to(new_language_root)
        flash[:notice] = _t(:language_pages_copied)
        redirect_to params[:layoutpage] == "true" ? admin_layoutpages_path : :action => :index
      end

      def sort
        @page_root = Page.language_root_for(session[:language_id])
        @sorting = true
      end

      def order
        @page_root = Page.language_root_for(session[:language_id])

        # Taken from https://github.com/matenia/jQuery-Awesome-Nested-Set-Drag-and-Drop
        neworder = JSON.parse(params[:set])
        prev_item = nil
        neworder.each do |item|
          dbitem = Page.find(item['id'])
          prev_item.nil? ? dbitem.move_to_child_of(@page_root) : dbitem.move_to_right_of(prev_item)
          sort_children(item, dbitem) unless item['children'].nil?
          prev_item = dbitem.reload
        end

        flash[:notice] = _t("Pages order saved")
        do_redirect_to admin_pages_path
      end

      def switch_language
        set_language(params[:language_id])
        do_redirect_to redirect_path_for_switch_language
      end

      def flush
        Page.with_language(session[:language_id]).flushables.each do |page|
          expire_action(page.cache_key)
        end
        respond_to do |format|
          format.js
        end
      end

      private

      def load_page
        @page = Page.find(params[:id])
      end

      def pages_from_raw_request
        request.raw_post.split('&').map { |i| i = {i.split('=')[0].gsub(/[^0-9]/, '') => i.split('=')[1]} }
      end

      # Taken from https://github.com/matenia/jQuery-Awesome-Nested-Set-Drag-and-Drop
      def sort_children(element, dbitem)
        prevchild = nil
        element['children'].each do |child|
          childitem = Page.find(child['id'])
          prevchild.nil? ? childitem.move_to_child_of(dbitem) : childitem.move_to_right_of(prevchild)
          sort_children(child, childitem) unless child['children'].nil?
          prevchild = childitem
        end
      end

      def redirect_path_for_switch_language
        if request.referer && request.referer.include?('admin/layoutpages')
          admin_layoutpages_path
        else
          admin_pages_path
        end
      end

      def redirect_path_after_create_page
        if @page.redirects_to_external?
          admin_pages_path
        else
          params[:redirect_to] || edit_admin_page_path(@page)
        end
      end

      def page_params
        params.require(:page).permit(*secure_attributes)
      end

      def secure_attributes
        if can?(:create, Alchemy::Page)
          Page::PERMITTED_ATTRIBUTES + [:language_root, :parent_id, :language_id, :language_code]
        else
          Page::PERMITTED_ATTRIBUTES
        end
      end

      def page_is_locked?
        return if !@page.locker.try(:logged_in?)
        @page.locked? && @page.locker != current_alchemy_user
      end

    end
  end
end
