class CreateJobs < ActiveRecord::Migration[8.0]
  def change
    create_table :jobs do |t|
      t.string :uuid, null: false, index: { unique: true }
      t.text :url, null: false
      t.boolean :render_js, default: true, null: false
      t.integer :max_pages, default: 1, null: false
      t.boolean :restrict_to_subpath, default: true, null: false
      t.integer :status, default: 0, null: false
      t.integer :progress, default: 0, null: false
      t.text :message
      t.integer :pages_crawled, default: 0, null: false
      t.integer :images_found, default: 0, null: false
      t.boolean :is_paid, default: true, null: false
      t.string :artifact_dir

      t.timestamps
    end

    add_index :jobs, :status
    add_index :jobs, :created_at
  end
end
