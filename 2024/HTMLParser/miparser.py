import asyncio, datetime, subprocess, os, sys, time
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
  end_time = now.replace(hour=16, minute=10, second=0, microsecond=0)

  if start_time <= now <= end_time:
      return True

  start_time2 = now.replace(hour=11, minute=30, second=0, microsecond=0)
  end_time2 = now.replace(hour=11, minute=40, second=0, microsecond=0)
  if start_time2 <= now <= end_time2:
      return True

  return False

# Read credentials from a file
def read_credentials(filename):
  """Reads confidential information from a file in the same directory as the parser.py.
  That file must have four lines with username, password, telegram_bot_token, telegram_chat_id

  Args:
    filename: The name of the file containing the credentials.

  Returns:
    A tuple containing the username, password, telegram_token, telegram_chat_ID
  """
  file_path = os.path.dirname(os.path.abspath(__file__))
  path = file_path + "/" + filename
  with open(path, "r") as f:
    username = f.readline().strip()
    password = f.readline().strip()
    telegram_token = f.readline().strip()
    telegram_chat_id = f.readline().strip()
  return username, password, telegram_token, telegram_chat_id


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

def testing_get_opportunity_details(driver):

    print("Inside the testing_get_opportunity_details")

    # Find all the card elements using the derived XPath
    card_elements = driver.find_elements(By.XPATH, "//div[@class='slcnsf4 slcnsf5']/div")

    print("Did we find any card?")
    print(f"card_elements: {card_elements}")

    all_opportunities = []
    if card_elements:
        print(f"Found {len(card_elements)} cards.")
        for card in card_elements:
            opportunity_data = scrape_card(card)
            all_opportunities.append(opportunity_data)
            print(f"Processed card: {opportunity_data}")
    else:
        print("No cards found on the page.")

    print(f"\nAll opportunities: {all_opportunities}")

    # Filter out the opportunities where 'conseguidos_percentage' is None
    filtered_opportunities = [opp for opp in all_opportunities if opp.get("conseguidos_percentage") is not None]

    print(f"\nAll processed opportunities: {all_opportunities}")
    print(f"\nFiltered opportunities (with data): {filtered_opportunities}")

    return filtered_opportunities
 

def get_opportunity_details(driver):
    """
    Fetches details for each investment opportunity on the page.

    Args:
      driver: The Selenium webdriver instance.

    Returns:
      A list of dictionaries, where each dictionary contains details 
      for a single opportunity.
    """

    opportunities = []
    print("Inside the get_opportunity_details")

    print("There are cards")
    opportunity = {}

    # 1 - Check for "Operación asegurada"
    try:
        driver.find_element(By.XPATH, ".//span[contains(text(), 'Con seguro')]")
        opportunity["operacion_asegurada"] = True
    except:
        opportunity["operacion_asegurada"] = False

    # 2 - Fetch "Tipo interés neto"
    try:
        opportunity["tipo_interes"] = driver.find_element(By.XPATH, "//span[text()='Interés bruto']/following-sibling::h6").text
    except:
        opportunity["tipo_interes"] = None

    # 3 - Fetch "Conseguido"
    try:
        conseguido_div = driver.find_element(By.XPATH, "//div[contains(., 'Conseguido')]")

        # Find the h6 element within the parent div.
        conseguido_value = conseguido_div.find_element(By.CSS_SELECTOR, "h6").text

        # Extract the "100%" using string manipulation.
        percentage = conseguido_value.split("- ")[-1] #split the string at "- " and take the last element of the resulting list.
        opportunity["conseguidos_percentage"] = percentage
    except:
        opportunity["conseguidos_percentage"] = None

    return opportunity



def pretty_telegram(opportunity):
    if not opportunity["operacion_asegurada"]:
        asyncio.run(send_telegram(token, chat_id, "Operación no asegurada"))
        return
    message = "Operación asegurada\n \
    Tipo interés: " + opportunity["tipo_interes"] + "\n \
    Porcentaje conseguidos: " + opportunity["conseguidos_percentage"] + "\n"
    asyncio.run(send_telegram(token, chat_id, message))


print("Starting")

# Get credentials
username, password, token, chat_id = read_credentials("credentials.txt")

if not token or not chat_id or not username or not password:
    print("Missing environment variables")

# Set up Chrome options
chrome_options = Options()
chrome_options.add_argument("--headless")

# Set up the browser driver (replace with the path to your driver)
service = Service(executable_path="/usr/bin/chromedriver")
driver = webdriver.Chrome(service=service, options=chrome_options)

# Navigate to the website
driver.get("https://newapp.myinvestor.es/app/explore/investments/sego/projects")

# Find the username and password fields and fill them in
username_field = WebDriverWait(driver, 20).until(
    EC.presence_of_element_located((By.XPATH, "//input[@placeholder='DNI / NIE / Pasaporte']"))
)
username_field.send_keys(username)

password_field = driver.find_element(By.XPATH, "//input[@placeholder='Contraseña']")
password_field.send_keys(password)

try:
    login_button = WebDriverWait(driver, 20).until(
        EC.presence_of_element_located((By.CSS_SELECTOR, "button[type='submit']._6p0dh75"))
    )
    print("Login button found using CSS Selector")

    # Scroll to the button
    driver.execute_script("arguments[0].scrollIntoView(true);", login_button)

    # Wait for the login button to be enabled
    WebDriverWait(driver, 30).until(
        lambda driver: login_button.is_enabled()
    )

    login_button.click()
    print("Login button clicked")

except Exception as e:
    print(f"Error finding/clicking login button: {e}")
    print(driver.page_source) # Print the page source for debugging.
    driver.save_screenshot("error_screenshot.png") #save screenshot.

try:
    # Wait for login to complete (adjust time as needed)
    time.sleep(3)  # Give the site time to log you in

    # Open a new tab
    driver.execute_script("window.open('');")

    # Switch to the new tab
    driver.switch_to.window(driver.window_handles[1])
    driver.get("https://newapp.myinvestor.es/app/explore/investments/sego/projects")

    # Wait for an element that indicates successful login (e.g., a welcome message)
    WebDriverWait(driver, 20).until(EC.presence_of_element_located((By.XPATH, "//span[contains(text(), 'SEGO Factoring')]")))
    print("Login successful!")

except:
    print("Login failed.")
    asyncio.run(send_telegram(token, chat_id, "Error. Login failed"))
    sys.exit(-1)

try:
    # Check if the "no opportunities" message exists
    no_opportunities_message = WebDriverWait(driver, 30).until(
        EC.presence_of_element_located((By.XPATH, "//span[contains(text(), 'No hay nuevas oportunidades')]"))
    )
    print("No new opportunities available.")
    if time_for_alive_message():
        asyncio.run(send_telegram(token, chat_id, "Sigo vivo co. No hay nuevas oportunidades"))

except:
    # If the message is not found, notify using Linux notification
    print("New opportunities found! Sending notification...")
    driver.save_screenshot("screenshot.png")
    #
    # Using method 1
    opportunity = get_opportunity_details(driver)
    print(f"opportunity. Method1 : {opportunity}")
    if float(opportunity["conseguidos_percentage"].replace(",", ".").replace(" %", "")) < 97:
        subprocess.run(["notify-send", "New", "Item"])
        asyncio.run(send_telegram(token, chat_id, "New opportunities! Method1"))
        pretty_telegram(opportunity)

    # Using method 2
    opportunities = testing_get_opportunity_details(driver)
    for opp in opportunities:
        print(f"opportunity: Method2: {opp}")
        if float(opp["conseguidos_percentage"].replace(",", ".").replace(" %", "")) < 97:
            subprocess.run(["notify-send", "New", "Item"])
            asyncio.run(send_telegram(token, chat_id, "New opportunities! Method2"))
            pretty_telegram(opp)


# Close the browser (optional, you might want to keep it open for further actions)
driver.quit()
