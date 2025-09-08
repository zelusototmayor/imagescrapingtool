require "test_helper"

class UrlValidatorTest < ActiveSupport::TestCase
  test "should validate good URLs" do
    valid_urls = [
      "https://example.com",
      "http://example.com",
      "https://subdomain.example.com",
      "https://example.com:8080",
      "https://example.com/path/to/page"
    ]

    valid_urls.each do |url|
      assert UrlValidator.valid?(url), "#{url} should be valid"
    end
  end

  test "should reject invalid URLs" do
    invalid_urls = [
      "not-a-url",
      "ftp://example.com",
      "javascript:alert('xss')",
      nil,
      ""
    ]

    invalid_urls.each do |url|
      assert_not UrlValidator.valid?(url), "#{url} should be invalid"
    end
  end

  test "should reject localhost URLs" do
    localhost_urls = [
      "http://localhost",
      "https://localhost:4000",
      "http://127.0.0.1",
      "http://0.0.0.0"
    ]

    localhost_urls.each do |url|
      assert_not UrlValidator.valid?(url), "#{url} should be rejected (localhost)"
    end
  end

  test "should reject private IP addresses" do
    private_urls = [
      "http://192.168.1.1",
      "http://10.0.0.1", 
      "http://172.16.0.1"
    ]

    private_urls.each do |url|
      assert_not UrlValidator.valid?(url), "#{url} should be rejected (private IP)"
    end
  end

  test "should normalize URLs" do
    assert_equal "https://example.com/", UrlValidator.normalize("https://example.com")
    assert_equal "https://example.com/path", UrlValidator.normalize("https://example.com/path#fragment")
    assert_nil UrlValidator.normalize("invalid-url")
  end

  test "should extract origin" do
    validator = UrlValidator.new("https://example.com:8080/path?query=1")
    assert_equal "https://example.com:8080", validator.origin
  end
end