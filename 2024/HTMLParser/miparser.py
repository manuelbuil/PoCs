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
    cards = WebDriverWait(driver, 15).until(
        EC.presence_of_all_elements_located((By.XPATH, "//div[@class='card card-myinvestor-sombra margin-top-15']"))
    )
    
    for card in cards:
        opportunity = {}

        # 1 - Check for "Operación asegurada"
        try:
            card.find_element(By.XPATH, ".//span[contains(text(), 'Operación asegurada')]")
            opportunity["operacion_asegurada"] = True
        except:
            opportunity["operacion_asegurada"] = False

        # 2 - Fetch "Plazo"
        try:
            plazo_element = card.find_element(By.XPATH, ".//div[contains(., 'Plazo')]/following-sibling::div")
            opportunity["plazo"] = plazo_element.text  # Example: "71 días"
        except:
            opportunity["plazo"] = None

        # 3 - Fetch "Tipo interés neto"
        try:
            interes_element = card.find_element(By.XPATH, ".//div[contains(., 'Tipo interés neto')]/following-sibling::div")
            opportunity["tipo_interes_neto"] = interes_element.text.split()[0]  # Extract "5,60 %" and then split to get "5,60"
        except:
            opportunity["tipo_interes_neto"] = None

        try:
            conseguidos_div = card.find_element(By.XPATH, ".//div[contains(., 'Conseguidos') and contains(., 'Total')]")
            # Locate the following sibling <div> which contains the values
            values_div = conseguidos_div.find_element(By.XPATH, "./following-sibling::div")

            # Extract the text content from the first child <div> within values_div
            percentage_text = values_div.find_element(By.XPATH, "./div[1]").text

            # Extract the percentage value (e.g., '100,00 %')
            percentage = percentage_text.split("(")[-1].split(")")[0]
            print(f"percentage: {percentage}\n")
            opportunity["conseguidos_percentage"] = percentage
        except:
            opportunity["conseguidos_percentage"] = None

        opportunities.append(opportunity)

    return opportunities


def pretty_telegram(opportunity):
    if not opportunity["operacion_asegurada"]:
        asyncio.run(send_telegram(token, chat_id, "Operación no asegurada"))
        return
    message = "Operación asegurada\n \
    Plazo: " + opportunity["plazo"] + "\n \
    Tipo interés neto: " + opportunity["tipo_interes_neto"] + "\n \
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
    no_opportunities_message = WebDriverWait(driver, 15).until(
        EC.presence_of_element_located((By.XPATH, "//span[contains(text(), 'No hay nuevas oportunidades')]"))
    )
    print("No new opportunities available.")
    if time_for_alive_message():
        asyncio.run(send_telegram(token, chat_id, "Sigo vivo co. No hay nuevas oportunidades"))
    #asyncio.run(send_telegram(token, chat_id, "TESTING async!"))

except:
    # If the message is not found, notify using Linux notification
    print("New opportunities found! Sending notification...")
    asyncio.run(send_telegram(token, chat_id, "New opportunities!"))
    driver.save_screenshot("screenshot.png")
    opportunities = get_opportunity_details(driver)
    for opportunity in opportunities:
        print(f"opportunity: {opportunity}")
        if float(opportunity["conseguidos_percentage"].replace(",", ".").replace(" %", "")) < 97:
            subprocess.run(["notify-send", "New", "Item"])
            pretty_telegram(opportunity)

# Close the browser (optional, you might want to keep it open for further actions)
driver.quit()
