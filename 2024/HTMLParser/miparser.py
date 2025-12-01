import asyncio, datetime, logging, subprocess, os, sys, time
from telegram import Bot
from selenium import webdriver
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.chrome.service import Service
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC

def time_for_alive_message():
  """
  Checks the current time and prints a message if it's between 17:00 and 17:10.
  """
  now = datetime.datetime.now()
  start_time = now.replace(hour=16, minute=0, second=0, microsecond=0)
  end_time = now.replace(hour=16, minute=5, second=0, microsecond=0)

  if start_time <= now <= end_time:
      return True

  start_time2 = now.replace(hour=11, minute=30, second=0, microsecond=0)
  end_time2 = now.replace(hour=11, minute=35, second=0, microsecond=0)
  if start_time2 <= now <= end_time2:
      return True

  return False

# Read credentials from a file
def read_credentials(filename):
  """Reads confidential information from a file in the same directory as the parser.py.
  That file must have four lines with username, password, telegram_bot_token, telegram_chat_id, url

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
    """Sends a message to a Telegram chat synchronously."""
    bot = Bot(token=token)
    async with bot:
        await bot.send_message(chat_id=chat_id, text=message)

def  scrape_card(card_element):
    """Extracts information from a single card element."""
    opportunity = {}
    try:
        opportunity["tipo_interes"] = card_element.find_element(By.XPATH, ".//div[1]/div[3]/div[3]/div[1]/h6").text
    except:
        opportunity["tipo_interes"] = None

    # 2 - Con seguro (verificar si el texto existe)
    try:
        seguro_element = card_element.find_element(By.XPATH, ".//*[text()='Con seguro']")
        opportunity["operacion_asegurada"] = True
    except:
        opportunity["operacion_asegurada"] = False

    # 3 - Conseguido percentage
    try:
        conseguido_div = card_element.find_element(By.XPATH, ".//div[contains(., 'Conseguido')]")
        conseguido_value = conseguido_div.find_element(By.CSS_SELECTOR, "h6").text
        percentage = conseguido_value.split("- ")[-1]
        opportunity["conseguidos_percentage"] = percentage
    except:
        opportunity["conseguidos_percentage"] = None

    # Add other fields you want to scrape from the card here
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
 

def pretty_telegram(opportunity):
    if not opportunity["operacion_asegurada"]:
        asyncio.run(send_telegram(token, chat_id, "Operación no asegurada"))
        return
    message = "Operación asegurada\n \
    Tipo interés: " + opportunity["tipo_interes"] + "\n \
    Porcentaje conseguidos: " + opportunity["conseguidos_percentage"] + "\n"
    asyncio.run(send_telegram(token, chat_id, message))


def check_for_no_opportunities(driver):
    """
    Checks if the "no opportunities" message is displayed.

    Args:
        driver: The Selenium WebDriver instance.

    Returns:
        bool: True if the message is found (no opportunities), False otherwise.
    """
    try:
        # Use a short timeout here for a quicker check.  No need for a full 30 seconds.
        WebDriverWait(driver, 30).until(
            EC.presence_of_element_located((By.XPATH, "//span[contains(text(), 'No hay nuevas oportunidades')]"))
        )
        return True  # Indicate no opportunities
    except:
        return False  # Indicate that the message was not found, meaning there *might* be opportunities


def check_for_opportunities(driver):
    """
    Checks for new opportunities and handles notifications.

    Args:
        driver: The Selenium WebDriver instance.

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
        logger.info(f"opportunity: {opp}")
        if float(opp["conseguidos_percentage"].replace(",", ".").replace(" %", "")) < 97:
            subprocess.run(["notify-send", "New", "Item"])
            asyncio.run(send_telegram(token, chat_id, "New opportunities!"))
            pretty_telegram(opp)

    return True


def initialize():
    """
    Initializes the driver.

    Returns:
      driver
    """
    # Set up Chrome options
    chrome_options = Options()
    if not DEBUG_MODE:
        chrome_options.add_argument("--headless")

    # Set up the browser driver (replace with the path to your driver)
    service = Service(executable_path="/usr/bin/chromedriver")
    driver = webdriver.Chrome(service=service, options=chrome_options)

    return driver

def login(driver):
    """
    Logs into the website

    Args:
      driver

    Returns:
        tuple: (telegram_token, telegram_chat_id) if login is successful and they are available.
    """

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

## Here starts the main program
DEBUG_MODE = os.getenv('DEBUG','0').lower() in ('1','true')

logging.basicConfig(
    level=logging.DEBUG if DEBUG_MODE else logging.INFO
)
logger = logging.getLogger("SEGO script")

logger.info(f"Starting script. DEBUG_MODE is {'ON' if DEBUG_MODE else 'OFF'}")
logging.getLogger("httpx").setLevel(logging.WARNING)
logging.getLogger("selenium").setLevel(logging.WARNING)
logging.getLogger("httpcore").setLevel(logging.WARNING)
logging.getLogger("urllib3").setLevel(logging.WARNING)

driver = initialize()
try:
    token, chat_id, url = login(driver)
except Exception as e:
    logger.error(f"Error login: {e}")
    sys.exit(-1)

try:
    # Wait for login to complete (adjust time as needed)
    time.sleep(14)  # Give the site time to log you in

    # Open a new tab
    driver.execute_script("window.open('');")

    # Switch to the new tab
    driver.switch_to.window(driver.window_handles[1])
    driver.get(url)

    # Wait for an element that indicates successful login (e.g., a welcome message)
    WebDriverWait(driver, 20).until(EC.presence_of_element_located((By.XPATH, "//span[contains(text(), 'SEGO Factoring')]")))
    logger.debug("Login successful!")

except:
    logger.error("Login failed.")
    asyncio.run(send_telegram(token, chat_id, "Error. Login failed"))
    sys.exit(-1)

try:
    if check_for_opportunities(driver):
        logger.debug("New opportunity notifications sent.")
    else:
        logger.info("No new opportunities available.")
        if time_for_alive_message():
            asyncio.run(send_telegram(token, chat_id, "Sigo vivo co. No hay nuevas oportunidades"))
finally:
    # Close the browser (optional, you might want to keep it open for further actions)
    if not DEBUG_MODE:
        driver.quit()
    else:
        time.sleep(100)
