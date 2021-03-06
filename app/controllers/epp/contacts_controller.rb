class Epp::ContactsController < EppController
  before_action :find_contact,  only: [:info, :update, :delete]
  before_action :find_password, only: [:info, :update, :delete]

  def info
    authorize! :info, @contact, @password
    render_epp_response 'epp/contacts/info'
  end

  def check
    authorize! :check, Epp::Contact

    ids = params[:parsed_frame].css('id').map(&:text)
    @results = Epp::Contact.check_availability(ids)
    render_epp_response '/epp/contacts/check'
  end

  def create
    authorize! :create, Epp::Contact
    @contact = Epp::Contact.new(params[:parsed_frame], current_user.registrar)

    @contact.add_legal_file_to_new(params[:parsed_frame])

    if @contact.save
      render_epp_response '/epp/contacts/create'
    else
      handle_errors(@contact)
    end
  end

  def update
    authorize! :update, @contact, @password

    if @contact.update_attributes(params[:parsed_frame], current_user)
      render_epp_response 'epp/contacts/update'
    else
      handle_errors(@contact)
    end
  end

  def delete
    authorize! :delete, @contact, @password

    if @contact.destroy_and_clean(params[:parsed_frame])
      render_epp_response '/epp/contacts/delete'
    else
      handle_errors(@contact)
    end
  end

  def renew
    authorize! :renew, Epp::Contact
    epp_errors << { code: '2101', msg: t(:'errors.messages.unimplemented_command') }
    handle_errors
  end

  private

  def find_password
    @password = params[:parsed_frame].css('authInfo pw').text
  end

  def find_contact
    code = params[:parsed_frame].css('id').text.strip.upcase

    @contact = Epp::Contact.find_by_epp_code(code)

    if @contact.blank?
      epp_errors << {
        code: '2303',
        msg: t('errors.messages.epp_obj_does_not_exist'),
        value: { obj: 'id', val: code }
      }
      fail CanCan::AccessDenied
    end
    @contact
  end

  #
  # Validations
  #
  def validate_info
    @prefix = 'info > info >'
    requires 'id'
  end

  def validate_check
    @prefix = 'check > check >'
    requires 'id'
  end

  def validate_create
    @prefix = 'create > create >'
    requires(
      'postalInfo > name', 'postalInfo > addr > street', 'postalInfo > addr > city',
      'postalInfo > addr > pc', 'postalInfo > addr > cc', 'voice', 'email'
    )
    ident = params[:parsed_frame].css('ident')

    if ident.present? && ident.attr('type').blank?
      epp_errors << {
        code: '2003',
        msg: I18n.t('errors.messages.required_ident_attribute_missing', key: 'type')
      }
    end

    if ident.present? && ident.text != 'birthday' && ident.attr('cc').blank?
      epp_errors << {
        code: '2003',
        msg: I18n.t('errors.messages.required_ident_attribute_missing', key: 'cc')
      }
    end
    # if ident.present? && ident.attr('cc').blank?
      # epp_errors << {
        # code: '2003',
        # msg: I18n.t('errors.messages.required_ident_attribute_missing', key: 'cc')
      # }
    # end
    contact_org_disabled
    fax_disabled
    status_editing_disabled
    @prefix = nil
    requires 'extension > extdata > ident'
  end

  def validate_update
    @prefix = 'update > update >'
    contact_org_disabled
    fax_disabled
    status_editing_disabled
    requires 'id'
    @prefix = nil
  end

  def validate_delete
    @prefix = 'delete > delete >'
    requires 'id'
    @prefix = nil
  end

  def contact_org_disabled
    return true if ENV['contact_org_enabled'] == 'true'
    return true if params[:parsed_frame].css('postalInfo org').text.blank?
    
    epp_errors << {
      code: '2306',
      msg: "#{I18n.t(:contact_org_error)}: postalInfo > org [org]"
    }
  end

  def fax_disabled
    return true if ENV['fax_enabled'] == 'true'
    return true if params[:parsed_frame].css('fax').text.blank?
    epp_errors << {
      code: '2306',
      msg: "#{I18n.t(:contact_fax_error)}: fax [fax]"
    }
  end

  def status_editing_disabled
    return true if Setting.client_status_editing_enabled
    return true if params[:parsed_frame].css('status').empty?
    epp_errors << {
      code: '2306',
      msg: "#{I18n.t(:client_side_status_editing_error)}: status [status]"
    }
  end
end
