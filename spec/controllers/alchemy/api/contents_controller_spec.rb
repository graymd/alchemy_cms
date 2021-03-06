require 'spec_helper'

module Alchemy
  describe Api::ContentsController do

    describe '#index' do
      let!(:page)    { create(:page) }
      let!(:element) { create(:element, page: page) }
      let!(:content) { create(:content, element: element) }

      it "returns all public contents as json objects" do
        alchemy_get :index, format: :json

        expect(response.status).to eq(200)
        expect(response.content_type).to eq('application/json')

        result = JSON.parse(response.body)

        expect(result).to have_key("contents")
        expect(result['contents'].size).to eq(Alchemy::Content.count)
      end

      context 'with element_id' do
        let!(:other_element) { create(:element, page: page) }
        let!(:other_content) { create(:content, element: other_element) }

        it "returns only contents from this element" do
          alchemy_get :index, element_id: other_element.id, format: :json

          expect(response.status).to eq(200)
          expect(response.content_type).to eq('application/json')

          result = JSON.parse(response.body)

          expect(result).to have_key("contents")
          expect(result['contents'].size).to eq(1)
          expect(result['contents'][0]['element_id']).to eq(other_element.id)
        end
      end

      context 'with empty element_id' do
        it "returns all contents" do
          alchemy_get :index, element_id: element.id, format: :json

          expect(response.status).to eq(200)
          expect(response.content_type).to eq('application/json')

          result = JSON.parse(response.body)

          expect(result).to have_key("contents")
          expect(result['contents'].size).to eq(Alchemy::Content.count)
        end
      end
    end

    describe '#show' do
      context 'with no other params given' do
        let(:page)    { create(:page) }
        let(:element) { create(:element, page: page) }
        let(:content) { create(:content, element: element) }

        before do
          expect(Content).to receive(:find).and_return(content)
        end

        it "returns content as json" do
          alchemy_get :show, id: content.id, format: :json

          expect(response.status).to eq(200)
          expect(response.content_type).to eq('application/json')

          result = JSON.parse(response.body)

          expect(result['id']).to eq(content.id)
        end

        context 'requesting an restricted content' do
          let(:page) { create(:page, restricted: true) }

          it "responds with 403" do
            alchemy_get :show, id: content.id, format: :json

            expect(response.content_type).to eq('application/json')
            expect(response.status).to eq(403)

            result = JSON.parse(response.body)

            expect(result).to have_key("error")
            expect(result['error']).to eq("Not authorized")
          end
        end
      end

      context 'with element_id and name params given' do
        let!(:page)    { create(:page) }
        let!(:element) { create(:element, page: page) }
        let!(:content) { create(:content, element: element) }

        it 'returns the named content from element with given id.' do
          alchemy_get :show, element_id: element.id, name: content.name, format: :json

          expect(response.status).to eq(200)
          expect(response.content_type).to eq('application/json')

          result = JSON.parse(response.body)

          expect(result['id']).to eq(content.id)
        end
      end

      context 'with empty element_id or name param' do
        it 'returns 404 error.' do
          alchemy_get :show, element_id: '', name: '', format: :json

          expect(response.status).to eq(404)
          expect(response.content_type).to eq('application/json')

          result = JSON.parse(response.body)

          expect(result).to have_key("error")
          expect(result['error']).to eq("Record not found")
        end
      end
    end
  end
end
