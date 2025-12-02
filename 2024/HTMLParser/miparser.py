import asyncio
import datetime
import logging
import subprocess
import os
import sys
import time
from telegram import Bot, error as telegram_error # Import specific error for better handling
from selenium import webdriver
from selenium.common.exceptions import NoSuchElementException, TimeoutException # Import specific Selenium exceptions
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.chrome.service import Service
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC

# --- Configuration and Utility Functions ---

def time_for_alive_message():
    """
    Checks the current time and returns True if it's within defined time windows
    (11:30-11:35 or 16:00-16:05).
    """
    now = datetime.datetime.now()

    # 16:00 to 16:05
    start_time_1 = now.replace(hour=16, minute=0, second=0, microsecond=0)
    end_time_1 = now.replace(hour=16, minute=5, second=0, microsecond=0)

    # 11:30 to 11:35
    start_time_2 = now.replace(hour=11, minute=30, second=0, microsecond=0)
    end_time_2 = now.replace(hour=11, minute=35, second=0, microsecond=0)

    if (start_time_1 <= now <= end_time_1) or \
       (start_time_2 <= now <= end_time_2):
        return True

    return False

def read_credentials(filename):
    """Reads confidential information from a file in the same directory as the script.

    The file must have five lines: username, password, telegram_bot_token, telegram_chat_id, url

    Args:
      filename: The name of the file containing the credentials.

    Returns:
      A tuple containing the username, password, telegram_token, telegram_chat_ID, url
    """
    file_path = os.path.dirname(os.path.abspath(__file__))
    path = file_path + "/" + filename
    with open(path, "r") as f:
      username = f.readline().strip()
      password = f.readline().strip()
      telegram_token = f.readline().strip()
      telegram_chat_id = f.readline().strip()
      url = f.readline().strip()
    return username, password, telegram_token, telegram_chat_id, url


async def send_telegram(token, chat_id, message):
    """Sends an asynchronous message to a Telegram chat."""
    try:
        bot = Bot(token=token)
        async with bot:
            await bot.send_message(chat_id=chat_id, text=message)
    except telegram_error.TelegramError as e:
        logger.error(f"Telegram error while sending message: {e}")
    except Exception as e:
        logger.error(f"Unexpected error while sending Telegram message: {e}")

def scrape_card(card_element):
    """Extracts information from a single card element."""
    opportunity = {}
    
    # 1 - Tipo Interes
    try:
        opportunity["tipo_interes"] = card_element.find_element(By.XPATH, ".//div[1]/div[3]/div[3]/div[1]/h6").text
    except NoSuchElementException: # Catch specific exception
        opportunity["tipo_interes"] = None

    # 2 - Con seguro (verificar si el texto existe)
    try:
        card_element.find_element(By.XPATH, ".//*[text()='Con seguro']")
        opportunity["operacion_asegurada"] = True
    except NoSuchElementException: # Catch specific exception
        opportunity["operacion_asegurada"] = False

    # 3 - Conseguido percentage
    try:
        conseguido_div = card_element.find_element(By.XPATH, ".//div[contains(., 'Conseguido')]")
        conseguido_value = conseguido_div.find_element(By.CSS_SELECTOR, "h6").text
        percentage = conseguido_value.split("- ")[-1]
        opportunity["conseguidos_percentage"] = percentage
    except NoSuchElementException: # Catch specific exception
        opportunity["conseguidos_percentage"] = None

    return opportunity

def get_opportunity_details(driver):
    # Find all the card elements using the derived XPath
    card_elements = driver.find_elements(By.XPATH, "//div[@class='slcnsf4 slcnsf5']/div")

    logger.debug(f"card_elements: {card_elements}")

    all_opportunities = []
    if card_elements:
        logger.debug(f"Found {len(card_elements)} cards.")
        for card in card_elements:
            opportunity_data = scrape_card(card)
            all_opportunities.append(opportunity_data)
            logger.debug(f"Processed card: {opportunity_data}")
    else:
        logger.debug("No cards found on the page.")

    logger.debug(f"\nAll opportunities: {all_opportunities}")

    # Filter out the opportunities where 'conseguidos_percentage' is None
    filtered_opportunities = [opp for opp in all_opportunities if opp.get("conseguidos_percentage") is not None]

    logger.debug(f"\nAll processed opportunities: {all_opportunities}")
    logger.debug(f"\nFiltered opportunities (with data): {filtered_opportunities}")

    return filtered_opportunities


async def pretty_telegram(opportunity, token, chat_id):
    """Formats and sends a Telegram message for a single opportunity."""
    if not opportunity["operacion_asegurada"]:
        await send_telegram(token, chat_id, "Operación no asegurada")
        return

    # Using f-strings and multiline strings (triple quotes) is cleaner than \
    message = f"""
Operación asegurada
Tipo interés: {opportunity["tipo_interes"]}
Porcentaje conseguidos: {opportunity["conseguidos_percentage"]}
"""
    await send_telegram(token, chat_id, message.strip())


def check_for_no_opportunities(driver):
    """Checks if the "no opportunities" message is displayed."""
    try:
        # Use a short timeout here for a quicker check.
        WebDriverWait(driver, 30).until(
            EC.presence_of_element_located((By.XPATH, "//span[contains(text(), 'No hay nuevas oportunidades')]"))
        )
        return True  # Indicate no opportunities
    except TimeoutException: # Catch specific exception
        return False  # Indicate that the message was not found, meaning there *might* be opportunities


async def check_for_opportunities(driver, token, chat_id):
    """
    Checks for new opportunities and handles notifications. Now an async function.

    Args:
        driver: The Selenium WebDriver instance.
        token: Telegram Bot Token
        chat_id: Telegram Chat ID

    Returns:
        bool: True if new opportunities were found, False otherwise.
    """
    if check_for_no_opportunities(driver):
        return False


    # If the message is not found, notify using Linux notification
    logger.info("New opportunities found! Sending notification...")
    if DEBUG_MODE:
        driver.save_screenshot("screenshot.png")

    opportunities = get_opportunity_details(driver)
    for opp in opportunities:
        logger.info(f"Opportunity: {opp}")

        # Safely convert percentage string to float
        try:
            percentage_str = opp["conseguidos_percentage"].replace(",", ".").replace(" %", "")
            percentage = float(percentage_str)
        except (ValueError, TypeError):
            logger.warning(f"Could not parse percentage for opportunity: {opp}")
            continue

        if percentage < 97:
            subprocess.run(["notify-send", "New", "Item"])
            await send_telegram(token, chat_id, "New opportunities!")
            await pretty_telegram(opp, token, chat_id)

    return True


def initialize():
    """Initializes the WebDriver."""
    # Set up Chrome options
    chrome_options = Options()
    if not DEBUG_MODE:
        chrome_options.add_argument("--headless")

    # Set up the browser driver (replace with the path to your driver)
    service = Service(executable_path="/usr/bin/chromedriver")
    driver = webdriver.Chrome(service=service, options=chrome_options)

    return driver

def login(driver):
    """Logs into the website and returns credentials."""
    # Get credentials
    username, password, token, chat_id, url = read_credentials("credentials.txt")

    if not token or not chat_id or not username or not password:
        raise Exception("Missing login variable")

    if not url:
        raise Exception("URL missing")

    # Navigate to the website
    driver.get(url)

    try:
        # Find the username and password fields and fill them in
        username_field = WebDriverWait(driver, 20).until(
            EC.presence_of_element_located((By.XPATH, "//input[@placeholder='DNI / NIE / Pasaporte']"))
        )
        username_field.send_keys(username)

        password_field = driver.find_element(By.XPATH, "//input[@placeholder='Contraseña']")
        password_field.send_keys(password)

        login_button = WebDriverWait(driver, 20).until(
            EC.presence_of_element_located((By.CSS_SELECTOR, "button[type='submit']._6p0dh75"))
        )
        logger.debug("Login button found using CSS Selector")

        # Scroll to the button
        driver.execute_script("arguments[0].scrollIntoView(true);", login_button)

        # Wait for the login button to be enabled
        WebDriverWait(driver, 30).until(
            lambda driver: login_button.is_enabled()
        )

        login_button.click()
        logger.debug("Login button clicked")

    except Exception as e:
        logger.error(f"Error with login: {e}")
        raise

    return token, chat_id, url

# --- Global Configuration and Main Execution ---

DEBUG_MODE = os.getenv('DEBUG','0').lower() in ('1','true')

# Set up logging before main execution
logging.basicConfig(
    level=logging.DEBUG if DEBUG_MODE else logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger("SEGO script")

# Suppress noisy library logs
logging.getLogger("httpx").setLevel(logging.WARNING)
logging.getLogger("selenium").setLevel(logging.WARNING)
logging.getLogger("httpcore").setLevel(logging.WARNING)
logging.getLogger("urllib3").setLevel(logging.WARNING)


async def main():
    """
    The main asynchronous execution function for the scraping script.
    """
    logger.info(f"Starting script. DEBUG_MODE is {'ON' if DEBUG_MODE else 'OFF'}")

    driver = initialize()

    try:
        token, chat_id, url = login(driver)
    except Exception as e:
        logger.error(f"Error during login setup: {e}")
        sys.exit(-1)

    try:
        # Wait for login to complete (adjust time as needed)
        time.sleep(14)  # Give the site time to log you in

        # Open a new tab
        driver.execute_script("window.open('');")

        # Switch to the new tab
        driver.switch_to.window(driver.window_handles[1])
        driver.get(url)

        # Wait for an element that indicates successful login
        WebDriverWait(driver, 20).until(EC.presence_of_element_located((By.XPATH, "//span[contains(text(), 'SEGO Factoring')]")))
        logger.debug("Login successful!")

    except TimeoutException:
        logger.error("Login failed")
        await send_telegram(token, chat_id, "Error. Login failed")
        sys.exit(-1)
    except Exception as e:
        logger.error(f"Unexpected error during post-login navigation: {e}")
        await send_telegram(token, chat_id, "Error. Login failed (Unexpected error).")
        sys.exit(-1)

    try:
        if await check_for_opportunities(driver, token, chat_id):
            logger.debug("New opportunity notifications sent.")
        else:
            logger.info("No new opportunities available.")
            if time_for_alive_message():
                await send_telegram(token, chat_id, "Sigo vivo co. No hay nuevas oportunidades")
    except Exception as e:
        logger.error(f"Error during opportunity check: {e}")
        await send_telegram(token, chat_id, f"Error during opportunity check: {str(e)}")

    finally:
        # Close the browser
        if not DEBUG_MODE:
            driver.quit()
        else:
            time.sleep(100)

if __name__ == "__main__":
    # Run the main asynchronous function
    asyncio.run(main())
