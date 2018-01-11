class VoteCompletion < ApplicationRecord
  belongs_to :election
  accepts_nested_attributes_for :election

  has_many :answers, as: :answerable

  accepts_nested_attributes_for :answers

  belongs_to :user

  VOTE_COMPLETION_TYPE_ONLINE =         'online'
  VOTE_COMPLETION_TYPE_PAPER =          'paper'
  VOTE_COMPLETION_TYPE_DISQUALIFIED =   'disqualified'

  scope :for_election,        ->(election)  { where(election: election) }
  scope :can_vote,            ->            {
                                              where(VoteCompletion.arel_table[:vote_type].not_eq(VOTE_COMPLETION_TYPE_DISQUALIFIED).and(
                                                 VoteCompletion.arel_table[:has_voted].eq(nil)
                                              ))
                                            }
  scope :completed,             ->          { where(has_voted: true) }
  scope :disqualifications,     ->          { where(vote_type: VOTE_COMPLETION_TYPE_DISQUALIFIED) }
  scope :not_disqualifications, ->          { where(VoteCompletion.arel_table[:vote_type].not_eq(VOTE_COMPLETION_TYPE_DISQUALIFIED)) }

  def disqualified?
    vote_type == VOTE_COMPLETION_TYPE_DISQUALIFIED
  end

  def available_to_vote?
    !has_voted
  end
end
