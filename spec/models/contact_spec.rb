require 'rails_helper'

describe Contact do
  before :all do
    Fabricate(:zonefile_setting, origin: 'ee')
    @api_user = Fabricate(:api_user)
  end

  context 'about class' do
    it 'should have versioning enabled?' do
      Contact.paper_trail_enabled_for_model?.should == true
    end

    it 'should have custom log prexied table name for versions table' do
      ContactVersion.table_name.should == 'log_contacts'
    end
  end

  context 'with invalid attribute' do
    before :all do
      @contact = Contact.new
    end

    it 'should not be valid' do
      @contact.valid?
      @contact.errors.full_messages.should match_array([
        "Name Required parameter missing - name",
        "Phone Required parameter missing - phone",
        "Phone Phone nr is invalid",
        "Email Required parameter missing - email",
        "Email Email is invalid",
        "Ident Required parameter missing - ident",
        "Registrar is missing",
        "Ident type is missing",
        "City is missing",
        "Country code is missing",
        "Street is missing",
        "Zip is missing"
      ])
    end

    it 'should not have creator' do
      @contact.creator.should == nil
    end

    it 'should not have updater' do
      @contact.updator.should == nil
    end

    it 'phone should return false' do
      @contact.phone = '32341'
      @contact.valid?
      @contact.errors[:phone].should == ["Phone nr is invalid"]
    end

    it 'should require country code when org' do
      @contact.ident_type = 'org'
      @contact.valid?
      @contact.errors[:ident_country_code].should == ['is missing']
    end

    it 'should require country code when priv' do
      @contact.ident_type = 'priv'
      @contact.valid?
      @contact.errors[:ident_country_code].should == ['is missing']
    end

    it 'should validate correct country code' do
      @contact.ident_type = 'org'
      @contact.ident_country_code = 'EE'
      @contact.valid?

      @contact.errors[:ident_country_code].should == []
    end

    it 'should require valid country code' do
      @contact.ident = '123'
      @contact.ident_type = 'org'
      @contact.ident_country_code = 'INVALID'
      @contact.valid?

      @contact.errors[:ident].should ==
        ['Ident country code is not valid, should be in ISO_3166-1 alpha 2 format']
    end

    it 'should convert to alpha2 country code' do
      @contact.ident_type = 'org'
      @contact.ident_country_code = 'ee'
      @contact.valid?

      @contact.ident_country_code.should == 'EE'
    end

    it 'should not have any versions' do
      @contact.versions.should == []
    end

    it 'should not accept long code' do
      @contact.code = 'verylongcode' * 100
      @contact.valid?
      @contact.errors[:code].should == ['Contact code is too long, max 100 characters']
    end

    it 'should not allow double status' do
      @contact.statuses = ['ok', 'ok']
      @contact.valid?
      @contact.errors[:statuses].should == ['not uniq']
    end

    it 'should have no related domain descriptions' do
      @contact.related_domain_descriptions.should == {}
    end

    it 'should fully validate email syntax for new records' do
      @contact.email = 'not@correct'
      @contact.valid?
      @contact.errors[:email].should == ['Email is invalid']
    end

    it 'should have ident updated because the logic itself is dedicated for legacy contacts ' do
      @contact.ident_updated_at.should_not == nil
    end
  end

  context 'with valid attributes' do
    before :all do
      @contact = Fabricate(:contact)
    end

    it 'should be valid' do
      @contact.valid?
      @contact.errors.full_messages.should match_array([])
    end

    it 'should be valid twice' do
      @contact = Fabricate(:contact)
      @contact.valid?
      @contact.errors.full_messages.should match_array([])
    end

    it 'should have one version' do
      with_versioning do
        @contact.versions.reload.should == []
        @contact.name = 'New name'
        @contact.save
        @contact.errors.full_messages.should match_array([])
        @contact.versions.size.should == 1
      end
    end

    it 'should not have relation with domains' do
      @contact.domains_present?.should == false
    end

    it 'org should be valid' do
      @contact.ident_type = 'org'
      @contact.ident = '1234'
      @contact.valid?
      @contact.errors.full_messages.should match_array([])
    end

    it 'should not overwrite code' do
      old_code = @contact.code
      @contact.code = 'CID:REG1:should-not-overwrite-old-code-12345'
      @contact.save.should == true
      @contact.code.should == old_code
    end

    it 'should have static password' do
      @contact.auth_info.should == 'password'
    end

    it 'should have ok status by default' do
      @contact.statuses.should == %w(ok)
    end

    it 'should not remove ok status after save' do
      @contact.statuses.should == %w(ok)
      @contact.save
      @contact.statuses.should == %w(ok)
    end

    it 'should remove ok status when other non linked status present' do
      contact = Fabricate(:contact)
      contact.statuses = [Contact::SERVER_UPDATE_PROHIBITED]
      contact.statuses.should == [Contact::SERVER_UPDATE_PROHIBITED] # temp test
      contact.save
      contact.statuses.should == [Contact::SERVER_UPDATE_PROHIBITED]
    end

    it 'should have linked status when domain' do
      contact = Fabricate(:contact)
      tech_domain_contact = Fabricate(:tech_domain_contact, contact_id: contact.id)
      contact.statuses.should == %w(ok)
      domain = Fabricate(:domain, tech_domain_contacts: [tech_domain_contact])

      contact = domain.contacts.first
      contact.save
      contact.statuses.sort.should == %w(linked ok)

      contact = domain.contacts.second
      contact.save
      contact.statuses.sort.should == %w(linked ok)
    end

    it 'should not have linked status when no domain' do
      @admin_domain_contact = Fabricate(:admin_domain_contact, contact_id: @contact.id)
      @domain = Fabricate(:domain, admin_domain_contacts: [@admin_domain_contact])
      contact = @domain.contacts.first
      contact.save

      contact.statuses.sort.should == %w(linked ok)

      contact.domains.first.destroy
      contact.reload
      contact.statuses.should == %w(ok)
    end

    it 'should have code' do
      @contact.code.should =~ /FIXED:..../
    end

    it 'should have linked status when domain is created' do
      # @admin_domain_contact = Fabricate(:admin_domain_contact)
      # @domain = Fabricate(:domain, admin_domain_contacts: [@admin_domain_contact])
      # puts @domain.contacts.size
      # contact = @domain.contacts.first

      # contact.statuses.map(&:value).should == %w(ok linked)
    end

    it 'should save status notes' do
      contact = Fabricate(:contact)
      contact.statuses = ['serverDeleteProhibited', 'serverUpdateProhibited']
      contact.status_notes_array = [nil, 'update manually turned off']
      contact.status_notes['serverDeleteProhibited'].should == nil
      contact.status_notes['serverUpdateProhibited'].should == 'update manually turned off'
      contact.status_notes['someotherstatus'].should == nil
    end

    it 'should have ident already updated because the logic itself is only for legacy contacts' do
      @contact.ident_updated_at.should_not == nil
    end

    it 'should have not update ident updated at when initializing old contact' do
      # creating a legacy contact
      contact = Fabricate(:contact)
      contact.update_column(:ident_updated_at, nil)

      Contact.find(contact.id).ident_updated_at.should == nil
    end

    context 'as birthday' do
      before do
        @domain = Fabricate(:domain)
      end

      it 'should have related domain descriptions hash' do
        contact = @domain.registrant
        contact.reload # somehow it registrant_domains are empty?
        contact.related_domain_descriptions.should == { "#{@domain.name}" => [:registrant] }
      end

      it 'should have related domain descriptions hash when find directly' do
        contact = @domain.registrant
        Contact.find(contact.id).related_domain_descriptions.should == { "#{@domain.name}" => [:registrant] }
      end

      it 'should have related domain descriptions hash' do
        contact = @domain.contacts.first
        contact.related_domain_descriptions.should == { "#{@domain.name}" => [:admin] }
      end

      it 'should fully validate email syntax for old records' do
        old = @contact.email
        @contact.email = 'legacy@support-not-correct'
        @contact.valid?
        @contact.errors[:email].should == ['Email is invalid']
        @contact.email = old
      end
    end

    context 'as birthday' do
      before :all do
        @contact.ident_type = 'birthday'
      end

      it 'birthday should be valid' do
        valid = ['2012-12-11', '1990-02-16']
        valid.each do |date|
          @contact.ident = date
          @contact.valid?
          @contact.errors.full_messages.should match_array([])
        end
      end

      it 'birthday should be invalid' do
        invalid = ['123' '12/12/2012', 'aaaa', '12/12/12', '02-11-1999']
        invalid.each do |date|
          @contact.ident = date
          @contact.valid?
          @contact.errors.full_messages.should ==
            ["Ident Ident not in valid birthady format, should be YYYY-MM-DD"]
        end
      end
    end

    context 'with callbacks' do
      before :all do
        # Ensure callbacks are not taken out from other specs
        Contact.set_callback(:create, :before, :generate_auth_info)
      end

      context 'after create' do
        it 'should not generate a new code when code is present' do
          @contact = Fabricate.build(:contact,
                                     code: 'FIXED:new-code',
                                     auth_info: 'qwe321')
          @contact.code.should == 'FIXED:new-code' # still new record
          @contact.save.should == true
          @contact.code.should == 'FIXED:NEW-CODE'
        end

        it 'should not allaw to use same code' do
          @contact = Fabricate.build(:contact,
                                     code: 'FIXED:new-code',
                                     auth_info: 'qwe321')
          @contact.code.should == 'FIXED:new-code' # still new record
          @contact.save.should == true
          @contact.code.should == 'FIXED:NEW-CODE'

          @contact = Fabricate.build(:contact,
                                     code: 'FIXED:new-code',
                                     auth_info: 'qwe321')
          @contact.code.should == 'FIXED:new-code' # still new record
          @contact.valid?
          @contact.errors.full_messages.should == ["Code Contact id already exists"]
        end

        it 'should generate a new password' do
          @contact = Fabricate.build(:contact, code: '123asd', auth_info: nil)
          @contact.auth_info.should == nil
          @contact.save.should == true
          @contact.auth_info.should_not be_nil
        end

        it 'should not allow same code' do
          @double_contact = Fabricate.build(:contact, code: @contact.code)
          @double_contact.valid?
          @double_contact.errors.full_messages.should == ["Code Contact id already exists"]
        end

        it 'should allow supported code format' do
          @contact = Fabricate.build(:contact, code: 'CID:REG1:12345')
          @contact.valid?
          @contact.errors.full_messages.should == []
        end

        it 'should not allow unsupported characters in code' do
          @contact = Fabricate.build(:contact, code: 'unsupported!ÄÖÜ~?')
          @contact.valid?
          @contact.errors.full_messages.should == ['Code is invalid']
        end

        it 'should generate code if empty code is given' do
          @contact = Fabricate(:contact, code: '')
          @contact.code.should_not == ''
        end

        it 'should not ignore empty spaces as code and generate new one' do
          @contact = Fabricate.build(:contact, code: '    ')
          @contact.valid?.should == true
          @contact.code.should =~ /FIXED:..../
        end
      end

      context 'after update' do
        before :all do
          @contact = Fabricate.build(:contact,
                                     code: '123asd',
                                     auth_info: 'qwe321')
          @contact.save
          @contact.code.should == 'FIXED:123ASD'
          @auth_info = @contact.auth_info
        end

        it 'should not generate new code' do
          @contact.update_attributes(name: 'qevciherot23')
          @contact.code.should == 'FIXED:123ASD'
        end

        it 'should not generate new auth_info' do
          @contact.update_attributes(name: 'fvrsgbqevciherot23')
          @contact.auth_info.should == @auth_info
        end
      end
    end
  end
end

describe Contact, '.destroy_orphans' do
  before do
    Fabricate(:zonefile_setting, origin: 'ee')
    @contact_1 = Fabricate(:contact, code: 'asd12')
    @contact_2 = Fabricate(:contact, code: 'asd13')
  end

  it 'destroys orphans' do
    Contact.find_orphans.count.should == 2
    Contact.destroy_orphans
    Contact.find_orphans.count.should == 0
  end

  it 'should find one orphan' do
    Fabricate(:domain, registrant: Registrant.find(@contact_1.id))
    Contact.find_orphans.count.should == 1
    Contact.find_orphans.last.should == @contact_2
  end

  it 'should find no orphans' do
    Fabricate(:domain, registrant: Registrant.find(@contact_1.id), admin_contacts: [@contact_2])
    cc = Contact.count
    Contact.find_orphans.count.should == 0
    Contact.destroy_orphans
    Contact.count.should == cc
  end
end
