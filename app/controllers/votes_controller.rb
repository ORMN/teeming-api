class VotesController < ApplicationController
  def index
    @race = Race.find(params[:race_id])
    authorize @race, :vote?

    @votes = current_user.votes.for_race(@race).includes(:candidacy)
    @overflow_districts = {}

    breadcrumbs votes_breadcrumbs, "Vote"
  end

  def view
    @race = Race.find(params[:race_id])
    authorize @race, :view_vote?

    @votes = current_user.votes.for_race(@race).includes(:candidacy)

    breadcrumbs votes_breadcrumbs, "View Votes"
  end

  def create
    @race = Race.find(params[:race_id])
    authorize @race, :vote?

    breadcrumbs votes_breadcrumbs, "Vote"

    if params[:votes]
      @votes = params[:votes].keys.map do |candidacy_id|
        Vote.new(candidacy: Candidacy.find(candidacy_id), user: current_user, race: @race)
      end
    else
      @votes = []
    end

    valid, @overflow_districts = @race.votes_valid?(@votes)

    if params[:voter_email]
      user = User.find_by_email(params[:voter_email])
      @voter_email_error = "email not found"
      valid = false unless user
    else
      user = current_user
    end

    if valid
      @votes.each { |vote| vote.save }
      VoteCompletion.create(race: @race, user: user, has_voted: true)

      if params[:voter_email]
        flash[:notice] = "The vote has been recorded"
        redirect_to enter_race_votes_path(@race)
      else
        flash[:notice] = "Your votes have been recorded"
        redirect_to @race
      end

    else
      if params[:voter_email]
        render 'enter'
      else
        render 'index'
      end
    end
  end

  def tallies
    @race = Race.find(params[:race_id])
    authorize @race, :tallies?

    @tallies = @race.tally_votes

    breadcrumbs votes_breadcrumbs, "Vote"
  end

  def enter
    @race = Race.find(params[:race_id])
    authorize @race, :enter?

    @votes = []
    @overflow_districts = {}

    breadcrumbs votes_breadcrumbs, "Vote"
  end

  private

  def votes_breadcrumbs(include_link: true)
    [@race.name, race_path(@race)]
  end
end