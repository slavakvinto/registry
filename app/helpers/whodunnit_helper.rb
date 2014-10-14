module WhodunnitHelper
  def link_to_whodunnit(whodunnit)
    return nil unless whodunnit
    if whodunnit.include?('-EppUser')
      user = EppUser.find(whodunnit)
      return link_to(user.username, admin_epp_user_path(user))
    end
    user = User.find(whodunnit)
    return link_to(user.username, admin_user_path(user))
  rescue ActiveRecord::RecordNotFound
    return nil
  end

  def whodunnit_with_protocol(whodunnit)
    return nil unless whodunnit
    if whodunnit.include?('-EppUser')
      user = EppUser.find(whodunnit)
      return "#{user.username} (EPP)"
    end
    user = User.find(whodunnit)
    return user.username
  rescue ActiveRecord::RecordNotFound
    return nil
  end
end