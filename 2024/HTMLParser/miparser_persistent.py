import asyncio
import datetime
import logging
import subprocess
import os
import re
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


def env_int(name, default):
    """Reads an integer environment variable and falls back to default on invalid values."""
    value = os.getenv(name, str(default))
    try:
        return int(value)
    except ValueError:
        return default


def env_bool(name, default=False):
    """Reads a boolean environment variable."""
    value = os.getenv(name)
    if value is None:
        return default
    return value.lower() in ('1', 'true', 'yes', 'on')

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
    card_text = card_element.text or ""
    
    # 1 - Nombre / título
    try:
        opportunity["nombre"] = card_element.find_element(By.TAG_NAME, "h4").text
    except NoSuchElementException: # Catch specific exception
        opportunity["nombre"] = None

    # 2 - Tipo interes actual
    interest_match = re.search(r"Inter[eé]s\s+(?:bruto|neto)\s+([0-9]+(?:,[0-9]+)?\s*%)(?:\s+anual)?", card_text, flags=re.IGNORECASE)
    opportunity["tipo_interes"] = interest_match.group(1) if interest_match else None

    # 3 - Con seguro (verificar si el texto existe)
    try:
        card_element.find_element(By.XPATH, ".//*[text()='Con seguro']")
        opportunity["operacion_asegurada"] = True
    except NoSuchElementException: # Catch specific exception
        opportunity["operacion_asegurada"] = False

    # 4 - Conseguido percentage from visible card text
    conseguido_match = re.search(
        r"Conseguido\s+[\d\.,]+\s*€\s*-\s*([0-9]+(?:,[0-9]+)?)\s*%",
        card_text,
        flags=re.IGNORECASE,
    )
    opportunity["conseguidos_percentage"] = f"{conseguido_match.group(1)} %" if conseguido_match else None

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


def log_diagnostics_for_cards(driver):
    """Logs raw card data to help update broken selectors."""
    try:
        card_elements = driver.find_elements(By.XPATH, "//div[@class='slcnsf4 slcnsf5']/div")
        logger.warning(f"Diagnostic mode: found {len(card_elements)} raw cards with the current card selector.")

        for index, card in enumerate(card_elements[:2], start=1):
            try:
                card_text = (card.text or "").strip()
                logger.warning(f"Diagnostic card #{index} text:\n{card_text}")
            except Exception as e:
                logger.warning(f"Diagnostic card #{index} text extraction failed: {e}")

            try:
                card_html = driver.execute_script("return arguments[0].outerHTML;", card)
                logger.warning(f"Diagnostic card #{index} HTML:\n{card_html[:4000]}")
            except Exception as e:
                logger.warning(f"Diagnostic card #{index} HTML extraction failed: {e}")

        try:
            page_text = driver.find_element(By.TAG_NAME, "body").text
            logger.warning(f"Diagnostic page text snippet:\n{page_text[:4000]}")
        except Exception as e:
            logger.warning(f"Diagnostic page text extraction failed: {e}")
    except Exception as e:
        logger.warning(f"Diagnostic logging failed: {e}")


async def pretty_telegram(opportunity, token, chat_id):
    """Formats and sends a Telegram message for a single opportunity."""
    if not opportunity["operacion_asegurada"]:
        await send_telegram(token, chat_id, "Operación no asegurada")
        return

    # Using f-strings and multiline strings (triple quotes) is cleaner than \
    message = f"""
Operación asegurada
Proyecto: {opportunity.get("nombre")}
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


    # If the message is not found, there may be opportunities to parse.
    logger.info("Potential opportunity cards detected. Extracting details...")
    if DEBUG_MODE:
        driver.save_screenshot("screenshot.png")

    opportunities = get_opportunity_details(driver)
    if not opportunities and DIAGNOSTIC_LOGGING:
        log_diagnostics_for_cards(driver)

    if not opportunities:
        logger.info("Potential cards detected, but no parseable opportunities were found.")
        return False

    logger.info(f"Parsed {len(opportunities)} opportunities with percentage data.")

    eligible_notifications = 0

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
            eligible_notifications += 1
            subprocess.run(["notify-send", "New", "Item"])
            await send_telegram(token, chat_id, "New opportunities!")
            await pretty_telegram(opp, token, chat_id)

    if eligible_notifications == 0:
        logger.info("No parsed opportunities are below the notification threshold (97%).")
    else:
        logger.info(f"Sent notifications for {eligible_notifications} opportunities below 97%.")

    return True


def initialize():
    """Initializes the WebDriver."""
    # Set up Chrome options
    chrome_options = Options()
    if not (DEBUG_MODE or PERSISTENT_BROWSER):
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


def is_login_page(driver):
    """Returns True if the browser is currently showing the login page."""
    return len(driver.find_elements(By.XPATH, "//input[@placeholder='DNI / NIE / Pasaporte']")) > 0


def wait_for_authenticated_session(driver, timeout=20):
    """Waits until an element indicating authenticated session is present."""
    WebDriverWait(driver, timeout).until(
        EC.presence_of_element_located((By.XPATH, "//span[contains(text(), 'SEGO Factoring')]"))
    )


async def periodic_monitoring_loop(driver, token, chat_id, url):
    """Keeps browser session alive and checks opportunities periodically in a new tab."""
    logger.info(f"Persistent monitoring mode enabled. Interval: {CHECK_INTERVAL_SECONDS}s")

    while True:
        try:
            logger.info("Starting periodic opportunity check...")
            driver.switch_to.window(driver.window_handles[0])
            driver.execute_script("window.open('about:blank', '_blank');")
            driver.switch_to.window(driver.window_handles[-1])
            driver.get(url)

            if is_login_page(driver):
                logger.warning("Session appears logged out. Re-authenticating...")
                await send_telegram(token, chat_id, "Session expired. Re-authenticating...")

                driver.close()
                driver.switch_to.window(driver.window_handles[0])

                login(driver)
                time.sleep(POST_LOGIN_WAIT_SECONDS)
                wait_for_authenticated_session(driver, timeout=30)

                await send_telegram(token, chat_id, "Re-authentication successful. Monitoring resumed.")
            else:
                if await check_for_opportunities(driver, token, chat_id):
                    logger.debug("Opportunity check completed.")
                else:
                    logger.info("No new opportunities available.")
                    if time_for_alive_message():
                        await send_telegram(token, chat_id, "Sigo vivo co from laptop. No hay nuevas oportunidades")

        except Exception as e:
            logger.error(f"Error in monitoring loop: {e}")
            await send_telegram(token, chat_id, f"Error in monitoring loop: {str(e)}")

        finally:
            try:
                while len(driver.window_handles) > 1:
                    driver.switch_to.window(driver.window_handles[-1])
                    driver.close()
                driver.switch_to.window(driver.window_handles[0])
                driver.get(url)
            except Exception as e:
                logger.warning(f"Could not fully reset tabs/session state: {e}")

        await asyncio.sleep(CHECK_INTERVAL_SECONDS)

# --- Global Configuration and Main Execution ---

DEBUG_MODE = os.getenv('DEBUG','0').lower() in ('1','true')
PERSISTENT_BROWSER = os.getenv('PERSISTENT_BROWSER', '0').lower() in ('1', 'true')
CHECK_INTERVAL_SECONDS = env_int('CHECK_INTERVAL_SECONDS', 180)
POST_LOGIN_WAIT_SECONDS = env_int('POST_LOGIN_WAIT_SECONDS', 14)
DIAGNOSTIC_LOGGING = env_bool('DIAGNOSTIC_LOGGING', False)

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
    logger.info(
        f"Starting script. DEBUG_MODE={'ON' if DEBUG_MODE else 'OFF'} | "
        f"PERSISTENT_BROWSER={'ON' if PERSISTENT_BROWSER else 'OFF'}"
    )

    driver = initialize()

    try:
        token, chat_id, url = login(driver)
    except Exception as e:
        logger.error(f"Error during login setup: {e}")
        sys.exit(-1)

    try:
        time.sleep(POST_LOGIN_WAIT_SECONDS)
        wait_for_authenticated_session(driver, timeout=20)
        logger.debug("Login successful!")

    except TimeoutException:
        logger.error("Login failed")
        await send_telegram(token, chat_id, "Error. Login failed")
        sys.exit(-1)
    except Exception as e:
        logger.error(f"Unexpected error during post-login navigation: {e}")
        await send_telegram(token, chat_id, "Error. Login failed (Unexpected error).")
        sys.exit(-1)

    if PERSISTENT_BROWSER:
        try:
            await send_telegram(token, chat_id, f"Monitoring started in persistent mode. Interval={CHECK_INTERVAL_SECONDS}s")
            await periodic_monitoring_loop(driver, token, chat_id, url)
        finally:
            driver.quit()
        return

    try:
        if await check_for_opportunities(driver, token, chat_id):
            logger.debug("New opportunity notifications sent.")
        else:
            logger.info("No new opportunities available.")
            if time_for_alive_message():
                await send_telegram(token, chat_id, "Sigo vivo co from laptop. No hay nuevas oportunidades")
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
