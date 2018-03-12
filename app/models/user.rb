class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :trackable, :validatable,
         :confirmable

  ROLE_TYPE_USER = :user
  ROLE_TYPE_ADMIN = :admin
  ROLE_TYPES = [ROLE_TYPE_USER, ROLE_TYPE_ADMIN]

  has_many :event_rsvps
  accepts_nested_attributes_for :event_rsvps

  has_many :events, through: :event_rsvps

  has_many :candidacies
  accepts_nested_attributes_for :candidacies

  has_many :answers, dependent: :destroy
  accepts_nested_attributes_for :answers

  has_one  :member, dependent: :destroy
  accepts_nested_attributes_for :member

  has_many :votes
  has_many :vote_completions

  belongs_to :role

  has_many :role_assignments
  has_many :roles, through: :role_assignments

  has_many :officer_assignments
  has_many :officers, through: :officer_assignments

  has_many :shares

  before_save :setup_wizard

  attr_accessor :authorize_args

  def new_candidacy(race)
    Candidacy.new(user: self, race: race)
  end

  def admin?
    role == ROLE_TYPE_ADMIN
  end

  def share_name_with?(user)
    share_name
  end

  def share_email_with?(user)
    share_email
  end

  def share_phone_with?(user)
    share_phone
  end

  def share_address_with?(user)
    share_address
  end

  def accepted_bylaws
    self.accepted_bylaws_at.present?
  end

  def accepted_bylaws=(accepted)
    if accepted
      self.accepted_bylaws_at = Time.now
    else
      self.accepted_bylaws_at = nil
    end
  end

  def name
    member.name
  end

  def in_race?(race)
    candidacies.map(&:race).include?(race)
  end

  def is_disqualified_to_vote_in_election?(election)
    vote_completions.for_election(election).disqualifications.first
  end

  def can_vote_in_election?(election)
    vcs = vote_completions.for_election(election)
    vote_completions.for_election(election).can_vote.first
  end

  def voted_in_election?(election)
    vote_completions.for_election(election).completed.first
  end

  def update_role_from_roles(apply_chapter_scope: true, chapter: nil)
    privileges = []
    roles.each do |role|
      role.privileges.each do |privilege|
        unless privileges.select{|p| p.is_identical_to?(privilege)}.present?
          dup_privilege = privilege.dup
          if apply_chapter_scope
            dup_privilege.scope =  {chapter_id: chapter || member.chapter.id}.to_json
          end
          privileges.push(dup_privilege)
        end
      end
    end
    new_role = Role.new(combined: true, name: 'combined')

    if self.role
      if privileges.present?
        if Set.new(self.role.privileges.map(&:to_hash)) != Set.new(privileges.map(&:to_hash))
          self.role.privileges = privileges.to_a
        end
      else
        self.role = nil
        self.save
      end
    else
      if privileges.present?
        new_role.privileges = privileges
        self.role = new_role
        self.save
      end
    end
  end

  def method_missing(sym, *args, &block)
    m = /^(can_|scope_for_)(.*)$/.match(sym.to_s)
    if m && m[1] == "can_"
      if role
        if role.respond_to?(sym)
          role.send(sym, *args)
        else
          raise "unknown privilege: #{sym}"
        end
      else
        false
      end
    elsif m && m[1] == "scope_for_"
      if role
        if role.respond_to?(sym)
          role.send(sym)
        else
          raise "unknown privilege: #{sym}"
        end
      else
        nil
      end
    else
      super
    end
  end

  private

  def role_for
  end

  def setup_wizard
    self.setup_state = 'step_setup_user_details' unless self.persisted?
  end
end

