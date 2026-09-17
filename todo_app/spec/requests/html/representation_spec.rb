require "rails_helper"

RSpec.describe "表現の固定", type: :request do
  let!(:list) { List.create!(name: "テスト用リスト") }

  it "HTML側は Accept: application/json を付けてもHTMLを返す" do
    get "/lists", headers: { "Accept" => "application/json" }

    expect(response.media_type).to eq("text/html")
  end

  it "ルートも Accept: application/json でHTMLを返す" do
    get "/", headers: { "Accept" => "application/json" }

    expect(response.media_type).to eq("text/html")
  end

  it "JSON側は Accept: text/html を付けてもJSONを返す" do
    get "/api/lists", headers: { "Accept" => "text/html" }

    expect(response.media_type).to eq("application/json")
  end

  it "拡張子ではHTML側からJSONに到達できない" do
    get "/lists.json"

    expect(response).to have_http_status(:not_found)
    expect(response.media_type).to eq("text/html")
  end

  it "拡張子ではJSON側からHTMLに到達できない" do
    get "/api/lists.html"

    expect(response).to have_http_status(:not_found)
    expect(response.media_type).to eq("application/json")
  end
end
