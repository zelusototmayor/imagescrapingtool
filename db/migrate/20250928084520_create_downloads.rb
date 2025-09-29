class CreateDownloads < ActiveRecord::Migration[8.0]
  def change
    create_table :downloads do |t|
      t.references :user, null: true, foreign_key: true
      t.references :job, null: false, foreign_key: true
      t.string :ip_address
      t.string :session_id
      t.datetime :downloaded_at

      t.timestamps
    end
  end
end
