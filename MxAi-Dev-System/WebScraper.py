import requests
from bs4 import BeautifulSoup

def scrape_website(url):
    """
    This function takes a URL as input, scrapes the website, and returns the parsed HTML.
    """
    try:
        response = requests.get(url)
        response.raise_for_status()  # Raise an exception for bad status codes
        soup = BeautifulSoup(response.content, 'html.parser')
        return soup
    except requests.exceptions.RequestException as e:
        print(f"Error scraping website: {e}")
        return None

if __name__ == "__main__":
    # Example usage:
    sample_url = "http://books.toscrape.com/"
    print(f"Scraping {sample_url}...")
    scraped_data = scrape_website(sample_url)

    if scraped_data:
        # Print the title of the page
        print("Page Title:", scraped_data.title.string)

        # Find and print all the book titles on the page
        books = scraped_data.find_all('h3')
        for book in books:
            print("Book Title:", book.a['title'])