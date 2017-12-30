require 'rails_helper'

describe VotesController do
  include Devise::Test::ControllerHelpers

  let!(:questionnaire)           { FactoryGirl.create(:questionnaire) }
  let!(:questionnaire_section_1) { FactoryGirl.create(:questionnaire_section, questionnaire: questionnaire, order_index: 1, title: 'Section 1') }
  let!(:ranked_choice_question)  { FactoryGirl.create(:question, questionnaire_section: questionnaire_section_1, question_type: Question::QUESTION_TYPE_RANKED_CHOICE, order_index: 1) }
  let!(:ranked_choice_1)         { FactoryGirl.create(:choice, question: ranked_choice_question, title: 'choice 1', order_index: 1) }
  let!(:ranked_choice_2)         { FactoryGirl.create(:choice, question: ranked_choice_question, title: 'choice 2', order_index: 2) }
  let(:valid_answer_attribute)   { { question_id: ranked_choice_question.id, text_ranked_choices: ["1", "0"] } }
  let(:invalid_answer_attribute) { { question_id: ranked_choice_question.id, text_ranked_choices: ["1", "1"] } }

  let(:election)                 { FactoryGirl.create(:election, :internal, :online_only,
                                                      questionnaire: questionnaire,
                                                      vote_date: Date.new(2017, 3, 10),
                                                      vote_start_time: Time.zone.local(2017, 3, 10, 16, 00),
                                                      vote_end_time: Time.zone.local(2017, 3, 10, 16, 30))
                                 }
  let(:oao_election)             { FactoryGirl.create(:election, :internal, :online_and_offline,
                                                      questionnaire: questionnaire,
                                                      vote_date: Date.new(2017, 3, 10),
                                                      vote_start_time: Time.zone.local(2017, 3, 10, 16, 00),
                                                      vote_end_time: Time.zone.local(2017, 3, 10, 16, 30))
  }
  let(:offline_election)         { FactoryGirl.create(:election, :internal, :offline_only, questionnaire: questionnaire)}
  let(:race)                     { FactoryGirl.create(:race, election: election) }
  let(:user)                     { FactoryGirl.create(:user) }
  let(:offline_enter_role)       { FactoryGirl.create(:role, privileges: [FactoryGirl.create(:privilege, subject: 'vote', action: 'enter')])}
  let(:offline_enter_user)       { FactoryGirl.create(:user, email: 'offline@enter.org', role: offline_enter_role)}

  describe "vote" do
    before do
      sign_in user
    end

    it "redirects to disqualified if the user tries to vote" do
      VoteCompletion.create(user: user, election: election, has_voted: false, vote_type: VoteCompletion::VOTE_COMPLETION_TYPE_DISQUALIFIED)
      get :index, params: { election_id: election.id }
      expect(response).to redirect_to(disqualified_election_votes_path(election_id: election.id))
    end

    it "redirects to wait if the time is before the vote start" do
      Timecop.freeze(Time.zone.local(2017, 3, 10, 15, 59, 59))
      get :index, params: { election_id: election.id }
      expect(response).to redirect_to(wait_election_votes_path(election_id: election.id))
    end

    it "does not redirect if it is between vote start and end near the beginning" do
      FactoryGirl.create(:vote_completion, election: election, user: user)
      Timecop.freeze(Time.zone.local(2017, 3, 10, 16, 00, 00))
      get :index, params: { election_id: election.id }
      expect(response).to be_ok
    end

    it "does not redirect if it is between vote start and end near the end" do
      FactoryGirl.create(:vote_completion, election: election, user: user)
      Timecop.freeze(Time.zone.local(2017, 3, 10, 16, 29, 59))
      get :index, params: { election_id: election.id }
      expect(response).to be_ok
    end

    it "redirects to missed if the time is after the vote end and the user has not voted" do
      Timecop.freeze(Time.zone.local(2017, 3, 10, 16, 30, 00))
      get :index, params: { election_id: election.id }
      expect(response).to redirect_to(missed_election_votes_path(election_id: election.id))
    end

    it "redirects to view if the time is after the vote end and the user has voted" do
      Timecop.freeze(Time.zone.local(2017, 3, 10, 16, 30, 00))
      VoteCompletion.create(user: user, election: election, has_voted: true, vote_type: VoteCompletion::VOTE_COMPLETION_TYPE_ONLINE)
      get :index, params: { election_id: election.id }
      expect(response).to redirect_to(view_election_votes_path(election_id: election.id))
    end

    it "redirects to root if the index page is hit for an offline election" do
      get :index, params: { election_id: offline_election.id }
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq("only offline voting is allowed for this election")
    end
  end

  describe "create" do
    context "when doing an online election" do
      before do
        sign_in user
      end

      it "redirects to disqualified if the user tries to vote" do
        VoteCompletion.create(user: user, election: election, has_voted: false, vote_type: VoteCompletion::VOTE_COMPLETION_TYPE_DISQUALIFIED)
        post :create, params: { election_id: election.id }
        expect(response).to redirect_to(disqualified_election_votes_path(election_id: election.id))
      end

      it "re-renders the index page when a ranked choice vote is invalid" do
        vote_completion = VoteCompletion.create(user: user, election: election, vote_type: VoteCompletion::VOTE_COMPLETION_TYPE_ONLINE)
        Timecop.freeze(Time.zone.local(2017, 3, 10, 16, 00, 00))
        post :create, params: { election_id: election.id, vote_completion: { answers_attributes: { "0" => invalid_answer_attribute} } }
        expect(response).to be_ok
        expect(render_template(:index)).to be_truthy
        expect(assigns(:vote_completion).answers.first.errors.present?).to be_truthy
        expect(vote_completion.reload.has_voted).to be_falsy
      end

      it "redirects to voted page when a ranked choice vote is valid" do
        vote_completion = VoteCompletion.create(user: user, election: election, vote_type: VoteCompletion::VOTE_COMPLETION_TYPE_ONLINE)
        Timecop.freeze(Time.zone.local(2017, 3, 10, 16, 00, 00))
        post :create, params: { election_id: election.id, vote_completion: { answers_attributes: { "0" => valid_answer_attribute} } }
        expect(response).to redirect_to(view_election_votes_path(election_id: election.id))
        expect(vote_completion.reload.has_voted).to be_truthy
      end
    end

    context "when doing an online and offline election" do
      before do
        sign_in offline_enter_user
      end

      it "re-renders the enter page when an email for a user can't vote in this election" do
        Timecop.freeze(Time.zone.local(2017, 3, 10, 16, 00, 00))
        VoteCompletion.create(election: oao_election, has_voted: true, user: user, vote_type: VoteCompletion::VOTE_COMPLETION_TYPE_ONLINE)
        post :create, params: { election_id: oao_election.id, voter_email: user.email + "a", vote_completion: { answers_attributes: { "0" => valid_answer_attribute} } }
        expect(response).to be_ok
        expect(render_template(:enter)).to be_truthy
        expect(assigns(:voter_email_error)).to eq("email not found")
        expect(assigns(:vote_completion).answers.first.errors.present?).to be_falsy
      end

      it "re-renders the enter page when an email for a user has already voted online for this election" do
        Timecop.freeze(Time.zone.local(2017, 3, 10, 16, 00, 00))
        VoteCompletion.create(election: oao_election, has_voted: true, user: user, vote_type: VoteCompletion::VOTE_COMPLETION_TYPE_ONLINE)
        post :create, params: { election_id: oao_election.id, voter_email: user.email, vote_completion: { answers_attributes: { "0" => valid_answer_attribute} } }
        expect(response).to be_ok
        expect(render_template(:enter)).to be_truthy
        expect(assigns(:voter_email_error)).to eq("voter has already voted (online)")
        expect(assigns(:vote_completion).answers.first.errors.present?).to be_falsy
      end
    end

    context "when doing an offline only election" do
      before do
        sign_in offline_enter_user
      end

      it "re-renders the enter page when ballot identifier has already been used for this election" do
        VoteCompletion.create(election: offline_election, has_voted: true, ballot_identifier: "1", vote_type: VoteCompletion::VOTE_COMPLETION_TYPE_PAPER)
        post :create, params: { election_id: offline_election.id, ballot_identifier: "1", vote_completion: { answers_attributes: { "0" => valid_answer_attribute} } }
        expect(response).to be_ok
        expect(render_template(:enter)).to be_truthy
        expect(assigns(:ballot_identifier_error)).to eq("ballot already entered")
        expect(assigns(:vote_completion).answers.first.errors.present?).to be_falsy
      end

      it "re-renders the enter page when ranked choices are invalid" do
        post :create, params: { election_id: offline_election.id, ballot_identifier: "1", vote_completion: { answers_attributes: { "0" => invalid_answer_attribute} } }
        expect(response).to be_ok
        expect(render_template(:enter)).to be_truthy
        expect(assigns(:vote_completion).answers.first.errors.present?).to be_truthy
      end

      it "redirects to the enter page on a successful ballot entry" do
        post :create, params: { election_id: offline_election.id, ballot_identifier: "1", vote_completion: { answers_attributes: { "0" => valid_answer_attribute} } }
        expect(response).to redirect_to(enter_election_votes_path(offline_election))
      end
    end
  end

  describe "view" do
    before do
      sign_in user
    end

    it "redirects to disqualified if the user tries to vote" do
      VoteCompletion.create(user: user, election: election, has_voted: false, vote_type: VoteCompletion::VOTE_COMPLETION_TYPE_DISQUALIFIED)
      get :view, params: { election_id: election.id }
      expect(response).to redirect_to(disqualified_election_votes_path(election_id: election.id))
    end
  end
end
