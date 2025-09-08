# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2025_09_03_212416) do
  create_table "jobs", force: :cascade do |t|
    t.string "uuid", null: false
    t.text "url", null: false
    t.boolean "render_js", default: true, null: false
    t.integer "status", default: 0, null: false
    t.integer "progress", default: 0, null: false
    t.text "message"
    t.integer "pages_crawled", default: 0, null: false
    t.integer "images_found", default: 0, null: false
    t.boolean "is_paid", default: true, null: false
    t.string "artifact_dir"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "scrape_mode", default: 0, null: false
    t.index ["created_at"], name: "index_jobs_on_created_at"
    t.index ["scrape_mode"], name: "index_jobs_on_scrape_mode"
    t.index ["status"], name: "index_jobs_on_status"
    t.index ["uuid"], name: "index_jobs_on_uuid", unique: true
  end
end
