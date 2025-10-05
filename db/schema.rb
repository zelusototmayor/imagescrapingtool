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

ActiveRecord::Schema[8.0].define(version: 2025_09_28_084559) do
  create_table "downloads", force: :cascade do |t|
    t.integer "user_id"
    t.integer "job_id", null: false
    t.string "ip_address"
    t.string "session_id"
    t.datetime "downloaded_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["job_id"], name: "index_downloads_on_job_id"
    t.index ["user_id"], name: "index_downloads_on_user_id"
  end

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
    t.integer "user_id"
    t.index ["created_at"], name: "index_jobs_on_created_at"
    t.index ["scrape_mode"], name: "index_jobs_on_scrape_mode"
    t.index ["status"], name: "index_jobs_on_status"
    t.index ["user_id"], name: "index_jobs_on_user_id"
    t.index ["uuid"], name: "index_jobs_on_uuid", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.integer "subscription_status", default: 0, null: false
    t.string "stripe_customer_id"
    t.string "stripe_subscription_id"
    t.integer "downloads_used", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "downloads", "jobs"
  add_foreign_key "downloads", "users"
  add_foreign_key "jobs", "users"
end
