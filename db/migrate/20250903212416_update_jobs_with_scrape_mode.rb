class UpdateJobsWithScrapeMode < ActiveRecord::Migration[8.0]
  def change
    # Add the new scrape_mode column
    add_column :jobs, :scrape_mode, :integer, default: 0, null: false
    
    # Migrate existing data based on max_pages and restrict_to_subpath
    reversible do |dir|
      dir.up do
        # Convert existing jobs to the new format
        execute <<-SQL
          UPDATE jobs 
          SET scrape_mode = CASE 
            WHEN max_pages = 1 THEN 0
            WHEN max_pages > 1 AND restrict_to_subpath = true THEN 1
            WHEN max_pages > 1 AND restrict_to_subpath = false THEN 2
            ELSE 0
          END
        SQL
      end
    end
    
    # Remove the old columns
    remove_column :jobs, :max_pages, :integer
    remove_column :jobs, :restrict_to_subpath, :boolean
    
    # Add index for the new column
    add_index :jobs, :scrape_mode
  end
end
